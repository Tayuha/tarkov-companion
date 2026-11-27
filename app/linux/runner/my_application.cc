#include "my_application.h"

#include <cmath>
#include <cstring>

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdk.h>

#include "flutter/generated_plugin_registrant.h"

// Window policy shared with app/lib/src/window_geometry.dart. Keep the two in
// sync: the runner enforces the size through GTK, and Dart clamps a restored
// rectangle before sending it back.
static constexpr gint kMinWindowWidth = 800;
static constexpr gint kMinWindowHeight = 560;
static constexpr gint kDefaultWindowWidth = 1280;
static constexpr gint kDefaultWindowHeight = 720;
static constexpr guint kCloseFallbackSeconds = 3;

static constexpr char kWindowChannel[] = "dev.tarkovcompanion/window";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* window_channel;
  GtkWindow* window;
  gboolean close_requested;
  guint close_timeout_id;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlValue* rect_value(double x,
                           double y,
                           double width,
                           double height) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "x", fl_value_new_float(x));
  fl_value_set_string_take(map, "y", fl_value_new_float(y));
  fl_value_set_string_take(map, "width", fl_value_new_float(width));
  fl_value_set_string_take(map, "height", fl_value_new_float(height));
  return map;
}

static FlValue* window_rect_value(GtkWindow* window) {
  gint x = 0;
  gint y = 0;
  gint width = kDefaultWindowWidth;
  gint height = kDefaultWindowHeight;
  if (window != nullptr) {
    gtk_window_get_position(window, &x, &y);
    gtk_window_get_size(window, &width, &height);
  }
  if (width <= 0) {
    width = kDefaultWindowWidth;
  }
  if (height <= 0) {
    height = kDefaultWindowHeight;
  }
  return rect_value(x, y, width, height);
}

static FlValue* metrics_value(MyApplication* self) {
  FlValue* metrics = fl_value_new_map();
  fl_value_set_string_take(metrics, "window", window_rect_value(self->window));

  FlValue* areas = fl_value_new_list();
  gint primary_index = 0;
  gint area_index = 0;
  GdkDisplay* display = gdk_display_get_default();
  if (display != nullptr) {
    GdkMonitor* primary = gdk_display_get_primary_monitor(display);
    const gint count = gdk_display_get_n_monitors(display);
    for (gint index = 0; index < count; index++) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, index);
      if (monitor == nullptr) {
        continue;
      }
      GdkRectangle area = {};
      gdk_monitor_get_workarea(monitor, &area);
      fl_value_append_take(
          areas, rect_value(area.x, area.y, area.width, area.height));
      if (monitor == primary) {
        primary_index = area_index;
      }
      area_index++;
    }
  }
  fl_value_set_string_take(metrics, "workAreas", areas);
  fl_value_set_string_take(metrics, "primaryIndex",
                           fl_value_new_int(primary_index));
  return metrics;
}

static double number_value(FlValue* map, const gchar* key, double fallback) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  return fallback;
}

static void close_window(MyApplication* self) {
  if (self->close_timeout_id != 0) {
    g_source_remove(self->close_timeout_id);
    self->close_timeout_id = 0;
  }
  if (self->window != nullptr) {
    GtkWindow* window = self->window;
    self->window = nullptr;
    gtk_widget_destroy(GTK_WIDGET(window));
  }
}

// Called before Flutter renders its first frame.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (self->window != nullptr) {
    gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }
}

// Reports a moved or resized window to Dart, which debounces the database
// write. GTK emits this for every step of an interactive drag.
static gboolean window_configure_event_cb(GtkWidget* widget,
                                          GdkEventConfigure* event,
                                          gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window_channel != nullptr) {
    g_autoptr(FlValue) args = window_rect_value(GTK_WINDOW(widget));
    fl_method_channel_invoke_method(self->window_channel,
                                    "windowGeometryChanged", args, nullptr,
                                    nullptr, nullptr);
  }
  return FALSE;
}

static void window_destroy_cb(GtkWidget* widget, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window == GTK_WINDOW(widget)) {
    self->window = nullptr;
  }
}

// Lets Dart persist the final geometry before the window disappears. Returning
// TRUE blocks the default close until Dart calls the `close` method back. A
// timeout guarantees the window still closes if the Dart isolate is gone.
static gboolean close_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->close_timeout_id = 0;
  close_window(self);
  return G_SOURCE_REMOVE;
}

static void window_closing_cb(GObject* object,
                              GAsyncResult* result,
                              gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(object), result,
                                             &error);
  if (response == nullptr && error != nullptr) {
    g_warning("Window closing handshake failed: %s", error->message);
  }
  close_window(self);
}

static gboolean window_delete_event_cb(GtkWidget* widget,
                                       GdkEvent* event,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->close_requested) {
    return TRUE;
  }
  self->close_requested = TRUE;
  if (self->window_channel == nullptr) {
    return FALSE;
  }

  g_autoptr(FlValue) args = window_rect_value(GTK_WINDOW(widget));
  fl_method_channel_invoke_method(self->window_channel, "windowClosing", args,
                                  nullptr, window_closing_cb, self);
  self->close_timeout_id =
      g_timeout_add_seconds(kCloseFallbackSeconds, close_timeout_cb, self);
  return TRUE;
}

static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "getMetrics") == 0) {
    g_autoptr(FlValue) metrics = metrics_value(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(metrics));
  } else if (strcmp(method, "setGeometry") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (self->window == nullptr || args == nullptr ||
        fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad-geometry", "setGeometry expects a geometry map", nullptr));
    } else {
      const double x = number_value(args, "x", 0);
      const double y = number_value(args, "y", 0);
      const double width =
          number_value(args, "width", kDefaultWindowWidth);
      const double height =
          number_value(args, "height", kDefaultWindowHeight);
      gint pixel_width = static_cast<gint>(std::lround(width));
      gint pixel_height = static_cast<gint>(std::lround(height));
      if (pixel_width < kMinWindowWidth) {
        pixel_width = kMinWindowWidth;
      }
      if (pixel_height < kMinWindowHeight) {
        pixel_height = kMinWindowHeight;
      }
      gtk_window_move(self->window, static_cast<gint>(std::lround(x)),
                      static_cast<gint>(std::lround(y)));
      gtk_window_resize(self->window, pixel_width, pixel_height);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "focus") == 0) {
    if (self->window != nullptr) {
      gtk_window_present(self->window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "close") == 0) {
    close_window(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to window method call: %s", error->message);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  gtk_window_set_default_size(window, kDefaultWindowWidth,
                              kDefaultWindowHeight);

  GdkGeometry geometry = {};
  geometry.min_width = kMinWindowWidth;
  geometry.min_height = kMinWindowHeight;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  g_signal_connect(window, "configure-event",
                   G_CALLBACK(window_configure_event_cb), self);
  g_signal_connect(window, "delete-event",
                   G_CALLBACK(window_delete_event_cb), self);
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), self);

  // If you want to use a header bar, uncomment the following lines.
  // Header bars are commonly used in GNOME based desktop environments and
  // allow additional widgets to be added to the title bar.
  // See https://docs.gtk.org/gtk3/class.HeaderBar.html
  // GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  // gtk_widget_show(GTK_WIDGET(header_bar));
  // gtk_header_bar_set_show_close_button(header_bar, TRUE);
  // gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));

  gtk_window_set_title(window, "Tarkov Companion");

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kWindowChannel,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_method_call_cb, self,
                                            nullptr);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->close_timeout_id != 0) {
    g_source_remove(self->close_timeout_id);
    self->close_timeout_id = 0;
  }
  g_clear_object(&self->window_channel);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->dart_entrypoint_arguments = nullptr;
  self->window_channel = nullptr;
  self->window = nullptr;
  self->close_requested = FALSE;
  self->close_timeout_id = 0;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // The app enforces single-instance itself through a lock and socket in
  // XDG_RUNTIME_DIR, so GTK must not reject the second process before Dart can
  // forward the focus request and exit without opening the database.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}

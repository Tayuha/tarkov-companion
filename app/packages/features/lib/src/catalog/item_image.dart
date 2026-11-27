import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_tokens.dart';

/// The network side of the item-image cache.
///
/// The production implementation wraps [AllowlistedHttpClient], so the only
/// host it can reach is the documented allowlist (`assets.tarkov.dev`). Tests
/// inject a fake so a cache hit never touches the network.
abstract interface class ItemImageFetcher {
  Future<Uint8List> fetch(Uri uri);
}

/// Fetches item images through the allowlisted client and nothing else.
final class AllowlistedItemImageFetcher implements ItemImageFetcher {
  const AllowlistedItemImageFetcher(this._client);

  final AllowlistedHttpClient _client;

  @override
  Future<Uint8List> fetch(Uri uri) => _client.getBytes(uri);
}

/// A bounded, disk-backed cache for item artwork.
///
/// * **Lazy** — bytes are read only when [load] is called for a visible image,
///   so a long catalog never fetches off-screen rows.
/// * **Disk-backed** — each image is stored under [directory] by a stable hash
///   of its URL, so a second run and an offline session both hit the cache.
/// * **Bounded** — after a write the cache evicts least-recently-used files
///   until the directory is at or below [maxBytes]. Reads touch the file's
///   modification time, which is the LRU signal.
/// * **Failure-safe** — a malformed URL, a failed fetch, or an I/O error
///   returns `null`; the caller renders its placeholder. Nothing throws to the
///   widget tree.
///
/// The cache does not decode images: it returns bytes, and the widget layer
/// decides how to size them.
final class ItemImageCache {
  ItemImageCache({
    required this.directory,
    required this.fetcher,
    this.maxBytes = defaultMaxBytes,
    this.memoryEntries = 32,
  }) : assert(maxBytes > 0),
       assert(memoryEntries >= 0);

  /// Default disk budget: 32 MiB, enough for a few hundred icons.
  static const int defaultMaxBytes = 32 * 1024 * 1024;

  static const String _extension = '.img';

  /// Directory that holds the cached image files.
  final Directory directory;

  final ItemImageFetcher fetcher;

  /// Maximum total size of cached files. Eviction runs after every write.
  final int maxBytes;

  /// Number of decoded-byte buffers kept in memory; also LRU.
  final int memoryEntries;

  /// In-memory byte buffers, most-recently-used last.
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();

  int _sequence = 0;

  /// Returns the image bytes for [url], or `null` when the image is
  /// unavailable.
  ///
  /// A disk hit is served without calling [fetcher]: this is the offline path.
  Future<Uint8List?> load(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    final key = cacheKey(url);

    final memoryHit = _memory.remove(key);
    if (memoryHit != null) {
      _memory[key] = memoryHit;
      return memoryHit;
    }

    final file = _fileFor(key);
    try {
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _touch(file);
          _remember(key, bytes);
          return bytes;
        }
      }
    } on FileSystemException {
      // A broken cache file is a miss, not an error.
    }

    try {
      final bytes = await fetcher.fetch(uri);
      if (bytes.isEmpty) {
        return null;
      }
      await _write(file, bytes);
      _remember(key, bytes);
      await _evictIfNeeded(keep: file);
      return bytes;
    } on Object {
      return null;
    }
  }

  /// Number of image files currently on disk.
  int fileCount() {
    if (!directory.existsSync()) {
      return 0;
    }
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(_extension))
        .length;
  }

  /// Total size of the cached image files, in bytes.
  int diskBytes() {
    if (!directory.existsSync()) {
      return 0;
    }
    var total = 0;
    for (final file in directory.listSync().whereType<File>()) {
      if (file.path.endsWith(_extension)) {
        try {
          total += file.lengthSync();
        } on FileSystemException {
          // A file removed concurrently contributes nothing.
        }
      }
    }
    return total;
  }

  /// Stable file key for [url].
  ///
  /// FNV-1a over the UTF-8 bytes gives a deterministic name across runs
  /// (unlike `String.hashCode`), and the original file extension is kept only
  /// in the stored extension so the file is self-describing for debugging.
  static String cacheKey(String url) => _fnv1a(url);

  File _fileFor(String key) => File('${directory.path}/$key$_extension');

  Future<void> _write(File file, Uint8List bytes) async {
    try {
      await directory.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      // A read-only cache directory still lets the image render; the bytes are
      // in memory and the next load simply fetches again.
    }
  }

  /// Marks [file] as recently used so eviction keeps it.
  void _touch(File file) {
    _sequence++;
    try {
      file.setLastModifiedSync(
        DateTime.now().add(Duration(microseconds: _sequence)),
      );
    } on FileSystemException {
      // Timestamp updates are best-effort; a failure only affects LRU order.
    }
  }

  void _remember(String key, Uint8List bytes) {
    if (memoryEntries == 0) {
      return;
    }
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > memoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<void> _evictIfNeeded({required File keep}) async {
    final files = <File>[];
    if (!directory.existsSync()) {
      return;
    }
    try {
      files.addAll(
        directory.listSync().whereType<File>().where(
          (file) => file.path.endsWith(_extension),
        ),
      );
    } on FileSystemException {
      return;
    }

    var total = 0;
    final sizes = <File, int>{};
    for (final file in files) {
      try {
        final size = file.lengthSync();
        sizes[file] = size;
        total += size;
      } on FileSystemException {
        // Ignore a file that vanished.
      }
    }
    if (total <= maxBytes) {
      return;
    }

    files.sort((a, b) {
      final aTime = _lastModified(a);
      final bTime = _lastModified(b);
      return aTime.compareTo(bTime);
    });

    for (final file in files) {
      if (total <= maxBytes) {
        break;
      }
      if (file.path == keep.path) {
        continue;
      }
      final size = sizes[file] ?? 0;
      try {
        file.deleteSync();
        total -= size;
      } on FileSystemException {
        // Another process may have removed it already.
      }
    }

    // An image larger than the whole budget can never be retained: drop the
    // newest file too rather than exceed the contract. The caller already has
    // the bytes, so the current frame still renders.
    if (total > maxBytes) {
      try {
        keep.deleteSync();
      } on FileSystemException {
        // Best-effort; the budget is a cache policy, not data integrity.
      }
    }
  }

  static DateTime _lastModified(File file) {
    try {
      return file.lastModifiedSync();
    } on FileSystemException {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static String _fnv1a(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// An item image with a stable placeholder.
///
/// The image is requested only when this widget is built and only when [cache]
/// and [url] are both present. While loading, on failure, or with no cache it
/// renders the neutral placeholder, so the layout never shifts.
class ItemImage extends StatefulWidget {
  const ItemImage({
    super.key,
    required this.cache,
    required this.url,
    required this.size,
    this.iconSize,
    this.borderRadius,
    this.fit = BoxFit.contain,
    this.placeholderKey,
    this.imageKey,
  });

  final ItemImageCache? cache;

  /// Image URL from the bundle (`iconLink`), or `null` for an item without one.
  final String? url;

  final double size;
  final double? iconSize;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  /// Optional key for the placeholder container.
  final Key? placeholderKey;

  /// Optional key for the loaded image.
  final Key? imageKey;

  @override
  State<ItemImage> createState() => _ItemImageState();
}

class _ItemImageState extends State<ItemImage> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ItemImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cache != widget.cache) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final cache = widget.cache;
    final url = widget.url;
    if (cache == null || url == null || url.isEmpty) {
      return;
    }
    setState(() => _loading = true);
    final bytes = await cache.load(url);
    if (!mounted || url != widget.url || cache != widget.cache) {
      return;
    }
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        key: widget.imageKey,
        width: widget.size,
        height: widget.size,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
      );
    }
    if (_loading) {
      return _placeholder(context);
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      key: widget.placeholderKey,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.border),
        borderRadius:
            widget.borderRadius ?? BorderRadius.circular(tokens.radiusSm),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: widget.iconSize ?? widget.size * 0.42,
        color: tokens.dim,
      ),
    );
  }
}

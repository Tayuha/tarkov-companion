/**
 * Minimal JSONPath resolver for the subset used by json.tarkov.dev payloads:
 *
 *   $.data.items.*.name
 *   $.data.items.*.properties.slots[*].name
 *   $.data.tasks.*.objectives[*]..bodyParts[*]
 *   $.data.tasks.*['startRewards','finishRewards'][*].customization[*].name
 *
 * Supported grammar: `$`, `.key`, `.*`, `[n]`, `[*]`, `..key`, `..*`, and
 * quoted key unions `['a','b']` / `["a","b"]`. No filters or expressions;
 * anything else is a parse error and is reported by the caller rather than
 * aborting a run.
 *
 * Per RFC 9535, `.*` selects every child of an object *or* every element of
 * an array. `[*]` does the same for arrays.
 */

export type PathSegment =
  | { readonly kind: "key"; readonly key: string }
  | { readonly kind: "wildcard" }
  | { readonly kind: "index"; readonly index: number }
  | { readonly kind: "anyIndex" }
  | { readonly kind: "descendant"; readonly key: string }
  | { readonly kind: "descendantWildcard" }
  | { readonly kind: "union"; readonly keys: readonly string[] };

export type JsonPath = readonly PathSegment[];

export interface NodeRef {
  readonly parent: Record<string, unknown> | unknown[];
  readonly key: string | number;
}

const KEY_STOP = new Set([".", "["]);

/**
 * Parse `['a','b']` / `["a","b"]` / `['a']` into a key list. Returns null when
 * the contents are not a quoted key union.
 */
function parseKeyUnion(inner: string): string[] | null {
  const keys: string[] = [];
  let i = 0;

  while (i < inner.length) {
    while (inner[i] === " " || inner[i] === ",") i += 1;
    if (i >= inner.length) break;

    const quote = inner[i];
    if (quote !== "'" && quote !== '"') return null;

    const end = inner.indexOf(quote, i + 1);
    if (end === -1) return null;

    keys.push(inner.slice(i + 1, end));
    i = end + 1;

    while (inner[i] === " ") i += 1;
    if (i < inner.length && inner[i] !== ",") return null;
  }

  return keys.length > 0 ? keys : null;
}

export function parseJsonPath(path: string): JsonPath {
  if (!path.startsWith("$")) {
    throw new Error(`JSONPath must start with "$": ${path}`);
  }

  const segments: PathSegment[] = [];
  let i = 1;

  while (i < path.length) {
    const ch = path[i];

    if (ch === "." && path[i + 1] === ".") {
      i += 2;
      if (path[i] === "*") {
        segments.push({ kind: "descendantWildcard" });
        i += 1;
        continue;
      }
      const start = i;
      while (i < path.length && !KEY_STOP.has(path[i] as string)) {
        i += 1;
      }
      if (i === start) {
        throw new Error(`Empty descendant name in JSONPath: ${path}`);
      }
      segments.push({ kind: "descendant", key: path.slice(start, i) });
      continue;
    }

    if (ch === ".") {
      i += 1;
      if (path[i] === "*") {
        segments.push({ kind: "wildcard" });
        i += 1;
        continue;
      }
      const start = i;
      while (i < path.length && !KEY_STOP.has(path[i] as string)) {
        i += 1;
      }
      if (i === start) {
        throw new Error(`Empty property name in JSONPath: ${path}`);
      }
      segments.push({ kind: "key", key: path.slice(start, i) });
      continue;
    }

    if (ch === "[") {
      const end = path.indexOf("]", i);
      if (end === -1) {
        throw new Error(`Unterminated bracket in JSONPath: ${path}`);
      }
      const inner = path.slice(i + 1, end);
      if (inner === "*") {
        segments.push({ kind: "anyIndex" });
      } else if (/^\d+$/.test(inner)) {
        segments.push({ kind: "index", index: Number(inner) });
      } else {
        const keys = parseKeyUnion(inner);
        if (keys === null) {
          throw new Error(`Unsupported bracket selector "[${inner}]" in JSONPath: ${path}`);
        }
        segments.push({ kind: "union", keys });
      }
      i = end + 1;
      continue;
    }

    throw new Error(`Unexpected character "${ch}" in JSONPath: ${path}`);
  }

  return segments;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Return references to every node matched by the path, so callers can mutate
 * them in place. Nodes whose parent is the root value itself are not returned
 * (payload paths always address a child of `$`).
 */
export function collectNodes(root: unknown, segments: JsonPath): NodeRef[] {
  let cursors: Array<{ value: unknown; parent?: Record<string, unknown> | unknown[]; key?: string | number }> = [
    { value: root },
  ];

  for (const segment of segments) {
    const next: typeof cursors = [];

    for (const cursor of cursors) {
      const value = cursor.value;

      switch (segment.kind) {
        case "key": {
          if (isRecord(value) && Object.hasOwn(value, segment.key)) {
            next.push({ value: value[segment.key], parent: value, key: segment.key });
          }
          break;
        }
        case "wildcard": {
          if (isRecord(value)) {
            for (const key of Object.keys(value)) {
              next.push({ value: value[key], parent: value, key });
            }
          } else if (Array.isArray(value)) {
            value.forEach((item, index) => next.push({ value: item, parent: value, key: index }));
          }
          break;
        }
        case "anyIndex": {
          if (Array.isArray(value)) {
            value.forEach((item, index) => next.push({ value: item, parent: value, key: index }));
          } else if (isRecord(value)) {
            for (const key of Object.keys(value)) {
              next.push({ value: value[key], parent: value, key });
            }
          }
          break;
        }
        case "index": {
          if (Array.isArray(value) && segment.index < value.length) {
            next.push({ value: value[segment.index], parent: value, key: segment.index });
          }
          break;
        }
        case "union": {
          if (isRecord(value)) {
            for (const key of segment.keys) {
              if (Object.hasOwn(value, key)) {
                next.push({ value: value[key], parent: value, key });
              }
            }
          }
          break;
        }
        case "descendant":
        case "descendantWildcard": {
          const stack: typeof cursors = [{ value }];

          while (stack.length > 0) {
            const current = stack.pop();
            if (current === undefined) break;
            const node = current.value;

            if (isRecord(node)) {
              for (const key of Object.keys(node)) {
                const child = { value: node[key], parent: node, key };
                if (segment.kind === "descendantWildcard" || key === segment.key) {
                  next.push(child);
                }
                stack.push(child);
              }
            } else if (Array.isArray(node)) {
              node.forEach((item, index) => {
                stack.push({ value: item, parent: node, key: index });
              });
            }
          }
          break;
        }
      }
    }

    cursors = next;
    if (cursors.length === 0) break;
  }

  const refs: NodeRef[] = [];
  for (const cursor of cursors) {
    if (cursor.parent !== undefined && cursor.key !== undefined) {
      refs.push({ parent: cursor.parent, key: cursor.key });
    }
  }
  return refs;
}

export function readNode(ref: NodeRef): unknown {
  return (ref.parent as Record<string | number, unknown>)[ref.key];
}

export function writeNode(ref: NodeRef, value: unknown): void {
  (ref.parent as Record<string | number, unknown>)[ref.key] = value;
}

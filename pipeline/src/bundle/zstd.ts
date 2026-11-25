import { constants, zstdCompressSync, zstdDecompressSync } from "node:zlib";

/**
 * zstd output is deterministic for a fixed input and a fixed parameter set:
 * the library buffers the whole input, uses a single thread, seeds no random
 * state, and writes no timestamp into the frame. Only the compressor version
 * can change the bytes, so the compressor version is part of the bundle
 * reproducibility contract (see `docs/data-bundles.md`).
 *
 * `-3` matches the size measured in the design (items + maps + tasks compress
 * to ~1.98 MB) and keeps ingestion cheap on low-end devices.
 */
export const ZSTD_COMPRESSION_LEVEL = 3;

/** Explicit parameters so an environment default cannot change the bytes. */
const ZSTD_PARAMS: Readonly<Record<number, number>> = {
  [constants.ZSTD_c_compressionLevel]: ZSTD_COMPRESSION_LEVEL,
  // 0 disables worker threads; multi-threaded frames depend on job splitting.
  [constants.ZSTD_c_nbWorkers]: 0,
  // No xxhash trailer: the manifest already carries a SHA-256 over the frame.
  [constants.ZSTD_c_checksumFlag]: 0,
};

export function compressZstd(input: Uint8Array): Buffer {
  return zstdCompressSync(input, { params: { ...ZSTD_PARAMS } });
}

export function decompressZstd(input: Uint8Array): Buffer {
  return zstdDecompressSync(input);
}

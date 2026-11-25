import { execFile } from "node:child_process";
import { copyFile, mkdtemp, rm } from "node:fs/promises";
import { basename, join } from "node:path";
import { tmpdir } from "node:os";
import { z } from "zod";
import { assertAssetName } from "./assets.js";
import type {
  AssetRef,
  CreateReleaseInput,
  ReleaseAsset,
  ReleaseClient,
  ReleaseInfo,
  UploadAssetInput,
} from "./client.js";
import { ReleaseError } from "./errors.js";

/**
 * `ReleaseClient` over the `gh` CLI.
 *
 * Every command is an argument vector passed to `execFile`, never a shell
 * string, so tag and asset names cannot be interpreted as shell syntax. The
 * process environment is inherited, which is how `gh` picks up `GH_TOKEN` or
 * `GITHUB_TOKEN`; when only the latter is present we also expose it as
 * `GH_TOKEN` so nested gh invocations agree on the credential.
 *
 * Cancellation/quota handling is intentionally absent: `gh` already retries
 * transient GitHub failures and publication is a short, single-shot job.
 */

const GH_MAX_BUFFER = 64 * 1024 * 1024;

const ghAssetSchema = z.object({
  id: z.number().int(),
  name: z.string(),
  size: z.number().int().nonnegative(),
});

const ghReleaseSchema = z.object({
  id: z.number().int(),
  tag_name: z.string(),
  name: z.string().nullable(),
  html_url: z.string(),
  assets: z.array(ghAssetSchema),
});

type GhReleasePayload = z.infer<typeof ghReleaseSchema>;

/** Keep gh's documented precedence while making a lone `GITHUB_TOKEN` visible. */
export function resolveGhEnvironment(env: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  if (env["GH_TOKEN"] === undefined && env["GITHUB_TOKEN"] !== undefined) {
    return { ...env, GH_TOKEN: env["GITHUB_TOKEN"] };
  }
  return env;
}

function ghErrorMessage(args: readonly string[], error: Error, stderr: Buffer): ReleaseError {
  const code = (error as NodeJS.ErrnoException).code;
  const text = stderr.toString("utf8").trim();

  if (code === "ENOENT") {
    return new ReleaseError(
      "gh-not-found",
      "the GitHub CLI (gh) was not found on PATH; install it from https://cli.github.com",
    );
  }

  if (
    /not logged in|gh auth login|authentication (?:required|failed)|HTTP 401|Bad credentials/i.test(
      text,
    )
  ) {
    return new ReleaseError(
      "unauthenticated",
      `gh is not authenticated; run "gh auth login" or set GH_TOKEN/GITHUB_TOKEN` +
        (text.length === 0 ? "" : ` (${text})`),
    );
  }

  if (/HTTP 404|\bnot found\b/i.test(text)) {
    return new ReleaseError("not-found", text.length === 0 ? "not found" : text);
  }

  const command = args.slice(0, 2).join(" ");
  return new ReleaseError(
    "gh-failed",
    `gh ${command} failed: ${text.length === 0 ? error.message : text}`,
  );
}

function runGh(args: readonly string[]): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    execFile(
      "gh",
      args,
      {
        encoding: "buffer",
        env: resolveGhEnvironment(process.env),
        maxBuffer: GH_MAX_BUFFER,
      },
      (error, stdout, stderr) => {
        if (error !== null) {
          reject(ghErrorMessage(args, error, stderr));
          return;
        }
        resolve(stdout);
      },
    );
  });
}

async function runGhText(args: readonly string[]): Promise<string> {
  return (await runGh(args)).toString("utf8");
}

function toReleaseInfo(payload: GhReleasePayload): ReleaseInfo {
  return {
    tag: payload.tag_name,
    title: payload.name ?? payload.tag_name,
    url: payload.html_url,
    assets: payload.assets.map(
      (asset): ReleaseAsset => ({ id: asset.id, name: asset.name, size: asset.size }),
    ),
  };
}

function parseReleasePayload(stdout: string, tag: string): ReleaseInfo {
  let json: unknown;
  try {
    json = JSON.parse(stdout) as unknown;
  } catch (error) {
    throw new ReleaseError(
      "gh-failed",
      `gh returned invalid JSON for release "${tag}": ` +
        (error instanceof Error ? error.message : String(error)),
    );
  }
  const parsed = ghReleaseSchema.safeParse(json);
  if (!parsed.success) {
    throw new ReleaseError(
      "gh-failed",
      `gh returned an unexpected release shape for "${tag}": ` +
        parsed.error.issues.map((issue) => issue.message).join("; "),
    );
  }
  return toReleaseInfo(parsed.data);
}

export class GhReleaseClient implements ReleaseClient {
  /**
   * Fail fast with a typed error when `gh` is missing or unauthenticated.
   * Read-only: no release or asset is touched.
   */
  async ready(): Promise<void> {
    await runGhText(["--version"]);
    await runGhText(["auth", "status"]);
  }

  async getRelease(tag: string): Promise<ReleaseInfo | null> {
    try {
      const stdout = await runGhText(["api", `repos/{owner}/{repo}/releases/tags/${tag}`]);
      return parseReleasePayload(stdout, tag);
    } catch (error) {
      if (error instanceof ReleaseError && error.kind === "not-found") return null;
      throw error;
    }
  }

  async createRelease(input: CreateReleaseInput): Promise<ReleaseInfo> {
    await runGhText([
      "release",
      "create",
      input.tag,
      "--title",
      input.title,
      "--notes",
      input.notes,
      "--latest=false",
    ]);

    const release = await this.getRelease(input.tag);
    if (release === null) {
      throw new ReleaseError(
        "gh-failed",
        `gh reported creating release "${input.tag}" but it cannot be read back`,
      );
    }
    return release;
  }

  async uploadAsset(input: UploadAssetInput): Promise<void> {
    assertAssetName(input.name);
    assertAssetName(basename(input.filePath));

    // `gh release upload` names an asset after the file's basename. The local
    // bundle file is `<dataset>.jsonl.zst`; the published asset must be the
    // versioned `<dataset>-<sha12>.jsonl.zst`, so upload a copy under that name.
    if (basename(input.filePath) === input.name) {
      await runGhText(["release", "upload", input.tag, input.filePath, "--clobber"]);
      return;
    }

    const directory = await mkdtemp(join(tmpdir(), "tarkov-asset-"));
    try {
      const staged = join(directory, input.name);
      await copyFile(input.filePath, staged);
      await runGhText(["release", "upload", input.tag, staged, "--clobber"]);
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  }

  async deleteAsset(input: AssetRef): Promise<void> {
    assertAssetName(input.name);
    await runGhText(["release", "delete-asset", input.tag, input.name, "--yes"]);
  }

  async downloadAsset(input: AssetRef): Promise<Uint8Array | null> {
    const release = await this.getRelease(input.tag);
    if (release === null) return null;

    const asset = release.assets.find((candidate) => candidate.name === input.name);
    if (asset === undefined) return null;

    const bytes = await runGh([
      "api",
      "-H",
      "Accept: application/octet-stream",
      `repos/{owner}/{repo}/releases/assets/${String(asset.id)}`,
    ]);
    return new Uint8Array(bytes);
  }
}

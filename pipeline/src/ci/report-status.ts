import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { z } from "zod";

/**
 * CI status reporter for the scheduled data sync.
 *
 * The workflow keeps exactly one issue alive at a time:
 *
 * - failure: create `Data sync failing` (label `data-sync`) or update the
 *   existing one by reopening it and adding a comment;
 * - success: close that issue with a short comment when it is open.
 *
 * Every GitHub call goes through `gh` as an argument vector via `execFile`,
 * never a shell string. The runner is injectable so the whole lifecycle is
 * unit-tested without a network or a real repository.
 */

export const STATUS_ISSUE_TITLE = "Data sync failing";
export const STATUS_ISSUE_LABEL = "data-sync";
export const DEFAULT_MAX_LOG_LINES = 60;
export const DEFAULT_MAX_LOG_CHARS = 6000;

export interface CommandResult {
  readonly stdout: string;
  readonly stderr: string;
}

export type CommandRunner = (command: string, args: readonly string[]) => Promise<CommandResult>;

export const execFileRunner: CommandRunner = (command, args) =>
  new Promise((resolvePromise, reject) => {
    execFile(
      command,
      [...args],
      { encoding: "utf8", maxBuffer: 8 * 1024 * 1024, env: process.env },
      (error, stdout, stderr) => {
        if (error !== null) {
          const detail = stderr.trim().length > 0 ? stderr.trim() : error.message;
          reject(new Error(`${command} ${args.join(" ")} failed: ${detail}`));
          return;
        }
        resolvePromise({ stdout, stderr });
      },
    );
  });

const issueSchema = z.object({
  number: z.number().int().positive(),
  title: z.string(),
  state: z.string(),
  url: z.string(),
});

type Issue = z.infer<typeof issueSchema>;

export interface StatusReportOptions {
  readonly status: "failure" | "success";
  readonly runner: CommandRunner;
  readonly title?: string;
  readonly label?: string;
  readonly runUrl?: string | null;
  readonly mode?: string | null;
  readonly dataset?: string | null;
  readonly reason?: string | null;
  readonly logTail?: string | null;
}

export type StatusAction =
  | "created"
  | "commented"
  | "reopened-and-commented"
  | "closed"
  | "noop";

export interface StatusReportResult {
  readonly action: StatusAction;
  readonly issueNumber: number | null;
}

function issueSearch(title: string): string {
  return `${title} in:title`;
}

async function listIssues(runner: CommandRunner, label: string, title: string): Promise<Issue[]> {
  const result = await runner("gh", [
    "issue",
    "list",
    "--label",
    label,
    "--state",
    "all",
    "--search",
    issueSearch(title),
    "--json",
    "number,title,state,url",
    "--limit",
    "20",
  ]);

  let json: unknown;
  try {
    json = JSON.parse(result.stdout) as unknown;
  } catch {
    throw new Error("gh issue list returned invalid JSON");
  }

  const parsed = z.array(issueSchema).safeParse(json);
  if (!parsed.success) {
    throw new Error("gh issue list returned an unexpected issue shape");
  }
  return parsed.data.filter((issue) => issue.title === title);
}

function pickIssue(issues: readonly Issue[]): Issue | undefined {
  return (
    issues.find((issue) => issue.state.toUpperCase() === "OPEN") ??
    issues[0]
  );
}

async function ensureLabel(runner: CommandRunner, label: string): Promise<void> {
  // `--force` makes this idempotent: it updates color/description when the
  // label already exists instead of failing.
  await runner("gh", [
    "label",
    "create",
    label,
    "--force",
    "--description",
    "Scheduled data sync reports",
    "--color",
    "1D76DB",
  ]);
}

function failureBody(options: StatusReportOptions): string {
  const target =
    options.mode === null || options.mode === undefined
      ? "unknown"
      : options.dataset === null || options.dataset === undefined
        ? options.mode
        : `${options.mode}/${options.dataset}`;

  const lines: string[] = [
    "The scheduled data sync failed.",
    "",
    `- Run: ${options.runUrl ?? "unknown"}`,
    `- Failed mode/dataset: ${target}`,
  ];
  if (options.reason !== null && options.reason !== undefined && options.reason.length > 0) {
    lines.push(`- Reason: ${options.reason}`);
  }
  lines.push(
    "",
    "<details><summary>Log tail</summary>",
    "",
    "```",
    options.logTail ?? "(no log available)",
    "```",
    "",
    "</details>",
  );
  return lines.join("\n");
}

function successComment(runUrl: string | null | undefined): string {
  return `Data sync succeeded${runUrl === null || runUrl === undefined ? "" : `: ${runUrl}`}. Closing.`;
}

function parseCreatedIssueNumber(stdout: string): number | null {
  const match = /\/issues\/(\d+)\s*$/.exec(stdout.trim());
  return match === null ? null : Number(match[1]);
}

/**
 * Apply the failure/success lifecycle to the single status issue.
 */
export async function runStatusReport(options: StatusReportOptions): Promise<StatusReportResult> {
  const title = options.title ?? STATUS_ISSUE_TITLE;
  const label = options.label ?? STATUS_ISSUE_LABEL;

  const issues = await listIssues(options.runner, label, title);
  const existing = pickIssue(issues);

  if (options.status === "failure") {
    const body = failureBody(options);

    if (existing === undefined) {
      await ensureLabel(options.runner, label);
      const created = await options.runner("gh", [
        "issue",
        "create",
        "--title",
        title,
        "--label",
        label,
        "--body",
        body,
      ]);
      return { action: "created", issueNumber: parseCreatedIssueNumber(created.stdout) };
    }

    if (existing.state.toUpperCase() === "CLOSED") {
      await options.runner("gh", ["issue", "reopen", String(existing.number)]);
      await options.runner("gh", [
        "issue",
        "comment",
        String(existing.number),
        "--body",
        body,
      ]);
      return { action: "reopened-and-commented", issueNumber: existing.number };
    }

    await options.runner("gh", [
      "issue",
      "comment",
      String(existing.number),
      "--body",
      body,
    ]);
    return { action: "commented", issueNumber: existing.number };
  }

  if (existing === undefined || existing.state.toUpperCase() !== "OPEN") {
    return { action: "noop", issueNumber: existing?.number ?? null };
  }

  await options.runner("gh", [
    "issue",
    "close",
    String(existing.number),
    "--comment",
    successComment(options.runUrl),
  ]);
  return { action: "closed", issueNumber: existing.number };
}

/** Last `maxLines` lines, capped at `maxChars` from the end. */
export function extractLogTail(
  text: string,
  maxLines: number = DEFAULT_MAX_LOG_LINES,
  maxChars: number = DEFAULT_MAX_LOG_CHARS,
): string {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const tail = lines.slice(Math.max(0, lines.length - maxLines)).join("\n");
  return tail.length > maxChars ? tail.slice(tail.length - maxChars) : tail;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export interface ReportFailure {
  readonly mode: string | null;
  readonly dataset: string | null;
  readonly message: string | null;
}

/** First failed mode/dataset from the sync report, or null when unavailable. */
export async function readFailureFromReport(path: string): Promise<ReportFailure | null> {
  let json: unknown;
  try {
    json = JSON.parse(await readFile(resolve(path), "utf8")) as unknown;
  } catch {
    return null;
  }

  if (!isRecord(json) || !Array.isArray(json["modes"])) return null;

  for (const mode of json["modes"]) {
    if (!isRecord(mode) || mode["status"] !== "failed") continue;
    const modeName = typeof mode["mode"] === "string" ? mode["mode"] : null;
    const errors = mode["errors"];

    if (Array.isArray(errors)) {
      for (const error of errors) {
        if (!isRecord(error)) continue;
        return {
          mode: modeName,
          dataset: typeof error["dataset"] === "string" ? error["dataset"] : null,
          message: typeof error["message"] === "string" ? error["message"] : null,
        };
      }
    }

    return { mode: modeName, dataset: null, message: null };
  }

  return null;
}

export function defaultRunUrl(env: NodeJS.ProcessEnv): string | null {
  const runId = env["GITHUB_RUN_ID"];
  const repository = env["GITHUB_REPOSITORY"];
  if (runId === undefined || repository === undefined) return null;
  const server = env["GITHUB_SERVER_URL"] ?? "https://github.com";
  return `${server}/${repository}/actions/runs/${runId}`;
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      status: { type: "string" },
      "log-file": { type: "string" },
      report: { type: "string" },
      "run-url": { type: "string" },
      title: { type: "string" },
      label: { type: "string" },
    },
  });

  const status = values.status;
  if (status !== "failure" && status !== "success") {
    throw new Error("--status must be failure or success");
  }

  const logTail =
    values["log-file"] === undefined
      ? null
      : extractLogTail(await readFile(resolve(values["log-file"]), "utf8"));
  const failure =
    values.report === undefined ? null : await readFailureFromReport(values.report);

  const result = await runStatusReport({
    status,
    runner: execFileRunner,
    runUrl: values["run-url"] ?? defaultRunUrl(process.env),
    mode: failure?.mode ?? null,
    dataset: failure?.dataset ?? null,
    reason: failure?.message ?? null,
    logTail,
    ...(values.title === undefined ? {} : { title: values.title }),
    ...(values.label === undefined ? {} : { label: values.label }),
  });

  console.log(
    `data-sync ${status}: ${result.action}` +
      (result.issueNumber === null ? "" : ` (issue #${String(result.issueNumber)})`),
  );
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}

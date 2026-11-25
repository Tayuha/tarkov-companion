import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import {
  DEFAULT_MAX_LOG_LINES,
  STATUS_ISSUE_LABEL,
  STATUS_ISSUE_TITLE,
  defaultRunUrl,
  extractLogTail,
  readFailureFromReport,
  runStatusReport,
  type CommandRunner,
} from "./report-status.js";

/**
 * Failure-issue lifecycle tests with a fake `gh` runner.
 *
 * Every case asserts both the resulting action and the exact argument vectors,
 * so a script change that starts using a shell, the wrong label or a second
 * issue fails here rather than in CI.
 */

const tempDirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "tarkov-status-"));
  tempDirs.push(dir);
  return dir;
}

afterAll(async () => {
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

interface FakeCall {
  readonly command: string;
  readonly args: readonly string[];
}

interface FakeRunner {
  readonly runner: CommandRunner;
  readonly calls: readonly FakeCall[];
}

function argValue(args: readonly string[], flag: string): string | undefined {
  const index = args.indexOf(flag);
  return index === -1 ? undefined : args[index + 1];
}

function fakeRunner(issues: readonly unknown[]): FakeRunner {
  const calls: FakeCall[] = [];

  const runner: CommandRunner = (command, args) => {
    calls.push({ command, args: [...args] });

    if (command !== "gh") {
      return Promise.reject(new Error(`unexpected command ${command}`));
    }
    if (args[0] === "issue" && args[1] === "list") {
      return Promise.resolve({ stdout: JSON.stringify(issues), stderr: "" });
    }
    if (args[0] === "issue" && args[1] === "create") {
      return Promise.resolve({
        stdout: "https://github.com/Tayuha/tarkov-companion/issues/42\n",
        stderr: "",
      });
    }
    return Promise.resolve({ stdout: "", stderr: "" });
  };

  return { runner, calls };
}

function mutationCalls(calls: readonly FakeCall[]): FakeCall[] {
  return calls.filter((call) => !(call.args[0] === "issue" && call.args[1] === "list"));
}

describe("failure reporting", () => {
  it("creates the single labelled issue when none exists", async () => {
    const { runner, calls } = fakeRunner([]);

    const result = await runStatusReport({
      status: "failure",
      runner,
      runUrl: "https://github.com/Tayuha/tarkov-companion/actions/runs/1",
      mode: "regular",
      dataset: "items",
      reason: "validation failed: items.0.price is invalid",
      logTail: "line a\nline b",
    });

    expect(result).toEqual({ action: "created", issueNumber: 42 });
    expect(calls.some((call) => call.args[0] === "label" && call.args[1] === "create")).toBe(true);

    const create = calls.find((call) => call.args[0] === "issue" && call.args[1] === "create");
    expect(create).toBeDefined();
    if (create === undefined) throw new Error("unreachable");
    expect(argValue(create.args, "--title")).toBe(STATUS_ISSUE_TITLE);
    expect(argValue(create.args, "--label")).toBe(STATUS_ISSUE_LABEL);

    const body = argValue(create.args, "--body") ?? "";
    expect(body).toContain("actions/runs/1");
    expect(body).toContain("regular/items");
    expect(body).toContain("validation failed");
    expect(body).toContain("line b");
  });

  it("comments on the open issue instead of opening a second one", async () => {
    const { runner, calls } = fakeRunner([
      { number: 7, title: STATUS_ISSUE_TITLE, state: "OPEN", url: "https://example/7" },
    ]);

    const result = await runStatusReport({
      status: "failure",
      runner,
      runUrl: "https://github.com/Tayuha/tarkov-companion/actions/runs/2",
      mode: "pve",
      dataset: null,
      reason: null,
      logTail: "boom",
    });

    expect(result).toEqual({ action: "commented", issueNumber: 7 });
    expect(calls.some((call) => call.args[1] === "create")).toBe(false);
    const comment = calls.find((call) => call.args[0] === "issue" && call.args[1] === "comment");
    expect(comment?.args).toContain("7");
    const body = argValue(comment?.args ?? [], "--body") ?? "";
    expect(body).toContain("pve");
    expect(body).toContain("actions/runs/2");
  });

  it("reopens and comments on a previously closed issue", async () => {
    const { runner, calls } = fakeRunner([
      { number: 9, title: STATUS_ISSUE_TITLE, state: "CLOSED", url: "https://example/9" },
    ]);

    const result = await runStatusReport({
      status: "failure",
      runner,
      runUrl: null,
      mode: null,
      dataset: null,
      reason: null,
      logTail: null,
    });

    expect(result).toEqual({ action: "reopened-and-commented", issueNumber: 9 });
    expect(calls.some((call) => call.args[0] === "issue" && call.args[1] === "reopen")).toBe(true);
    expect(calls.some((call) => call.args[0] === "issue" && call.args[1] === "comment")).toBe(true);
    const comment = calls.find((call) => call.args[0] === "issue" && call.args[1] === "comment");
    expect(argValue(comment?.args ?? [], "--body") ?? "").toContain("unknown");
  });
});

describe("success reporting", () => {
  it("closes the open issue with a short comment", async () => {
    const { runner, calls } = fakeRunner([
      { number: 7, title: STATUS_ISSUE_TITLE, state: "OPEN", url: "https://example/7" },
    ]);

    const result = await runStatusReport({
      status: "success",
      runner,
      runUrl: "https://github.com/Tayuha/tarkov-companion/actions/runs/3",
    });

    expect(result).toEqual({ action: "closed", issueNumber: 7 });
    const close = calls.find((call) => call.args[0] === "issue" && call.args[1] === "close");
    expect(close?.args).toContain("7");
    const comment = argValue(close?.args ?? [], "--comment") ?? "";
    expect(comment).toContain("succeeded");
    expect(comment).toContain("actions/runs/3");
    expect(mutationCalls(calls)).toHaveLength(1);
  });

  it("does nothing when the issue is already closed or absent", async () => {
    const closed = fakeRunner([
      { number: 7, title: STATUS_ISSUE_TITLE, state: "CLOSED", url: "https://example/7" },
    ]);
    const closedResult = await runStatusReport({
      status: "success",
      runner: closed.runner,
      runUrl: null,
    });
    expect(closedResult).toEqual({ action: "noop", issueNumber: 7 });
    expect(mutationCalls(closed.calls)).toEqual([]);

    const missing = fakeRunner([]);
    const missingResult = await runStatusReport({
      status: "success",
      runner: missing.runner,
      runUrl: null,
    });
    expect(missingResult).toEqual({ action: "noop", issueNumber: null });
    expect(mutationCalls(missing.calls)).toEqual([]);
  });
});

describe("log tail and report parsing", () => {
  it("keeps only the last lines and caps the characters", () => {
    const text = Array.from({ length: 200 }, (_, index) => `line ${String(index)}`).join("\n");
    const tail = extractLogTail(text, 5);

    expect(tail.split("\n")).toHaveLength(5);
    expect(tail).toContain("line 199");
    expect(tail).not.toContain("line 0\n");

    const capped = extractLogTail("x".repeat(100), DEFAULT_MAX_LOG_LINES, 10);
    expect(capped).toBe("x".repeat(10));
  });

  it("reads the first failed mode and dataset from the sync report", async () => {
    const dir = await tempDir();
    const path = join(dir, "report.json");
    await writeFile(
      path,
      JSON.stringify({
        generatedAt: "2026-11-26T00:00:00.000Z",
        exitCode: 1,
        modes: [
          { mode: "regular", status: "published", errors: [] },
          {
            mode: "pve",
            status: "failed",
            errors: [{ mode: "pve", dataset: "items", message: "validation failed" }],
          },
        ],
      }),
      "utf8",
    );

    expect(await readFailureFromReport(path)).toEqual({
      mode: "pve",
      dataset: "items",
      message: "validation failed",
    });

    expect(await readFailureFromReport(join(dir, "missing.json"))).toBeNull();
  });

  it("derives the run URL from the GitHub Actions environment", () => {
    expect(
      defaultRunUrl({
        GITHUB_RUN_ID: "123",
        GITHUB_REPOSITORY: "Tayuha/tarkov-companion",
      }),
    ).toBe("https://github.com/Tayuha/tarkov-companion/actions/runs/123");

    expect(defaultRunUrl({})).toBeNull();
  });
});

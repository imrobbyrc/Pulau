import { describe, expect, test } from "bun:test";
import { Reporter } from "./reporter.ts";

describe("Pi subagent status reporter", () => {
  test("reports child lifecycle without exposing raw IDs", () => {
    const output: string[] = [];
    const reporter = new Reporter((value) => output.push(value));
    reporter.update("private-run", "private-task", "queued");
    expect(output).toHaveLength(0);
    reporter.update("private-run", "private-task", "running");
    expect(output).toHaveLength(1);
    expect(output[0]).toMatch(/^\x1b\]7501;state=working:id=pulau-subagents\/[a-f0-9]{16}:app=pi\x1b\\$/);
    expect(output[0]).not.toContain("private");
    reporter.update("private-run", "private-task", "running");
    expect(output).toHaveLength(1);
    reporter.update("private-run", "private-task", "awaiting_parent");
    reporter.update("private-run", "private-task", "completed");
    reporter.update("private-run", "private-task", "queued");
    expect(output[1]).toContain("state=blocked:");
    expect(output[2]).toContain("state=done:");
    expect(output[3]).toContain("state=clear:");
  });

  test("sends bounded first line safely and removes it on completion", () => {
    const output: string[] = [];
    const reporter = new Reporter((value) => output.push(value));
    reporter.update("run", "task", "queued", "First: task\x1b[31m\nPrivate second line");
    reporter.update("run", "task", "running");
    const encoded = output[0].match(/:msg=([^\x1b]+)/)?.[1];
    expect(encoded).toBeDefined();
    expect(Buffer.from(encoded!, "base64").toString()).toBe("First: task [31m");
    expect(output[0]).not.toContain("Private second line");
    reporter.update("run", "task", "completed");
    expect(output[1]).not.toContain(":msg=");
    reporter.update("run", "task", "running");
    expect(output[2]).not.toContain(":msg=");
    reporter.update("run", "task", "running", "x".repeat(100));
    const updated = output[3].match(/:msg=([^\x1b]+)/)?.[1];
    expect(Buffer.from(updated!, "base64").toString()).toHaveLength(80);
  });

  test("disable clears only plugin records and enable republishes latest state", () => {
    const output: string[] = [];
    const reporter = new Reporter((value) => output.push(value));
    reporter.update("a", "b", "running");
    reporter.setEnabled(false);
    expect(output[1]).toBe("\x1b]7501;state=clear:id=pulau-subagents\x1b\\");
    reporter.update("a", "b", "failed");
    expect(output).toHaveLength(2);
    reporter.setEnabled(true);
    expect(output[2]).toContain("state=error:");
    reporter.clear();
    expect(output[3]).toBe("\x1b]7501;state=clear:id=pulau-subagents\x1b\\");
  });

  test("reports the active Pi model separately and respects disable", () => {
    const output: string[] = [];
    const reporter = new Reporter((value) => output.push(value));
    reporter.setModel("anthropic", "claude-sonnet");
    expect(output[0]).toContain("state=idle:id=pulau-subagents/model:app=pi:msg=");
    expect(Buffer.from(output[0].match(/:msg=([^\x1b]+)/)![1], "base64").toString()).toBe("anthropic/claude-sonnet");
    reporter.setEnabled(false);
    reporter.setModel("openai", "gpt-5");
    expect(output).toHaveLength(2);
    reporter.setEnabled(true);
    expect(Buffer.from(output[2].match(/:msg=([^\x1b]+)/)![1], "base64").toString()).toBe("openai/gpt-5");
    reporter.setModel("bad\x1b", "invalid");
    expect(output[3]).toContain("state=clear:id=pulau-subagents/model");
  });

  test("invalid events never emit status", () => {
    const output: string[] = [];
    const reporter = new Reporter((value) => output.push(value));
    reporter.update(null, "b", "running");
    reporter.update("a", undefined, "running");
    reporter.update("a", "b", null);
    expect(output).toHaveLength(0);
  });
});

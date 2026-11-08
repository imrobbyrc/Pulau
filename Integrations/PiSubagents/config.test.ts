import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readGlobalEnabled, reportingIssue } from "./config.ts";

describe("Pulau global Pi plugin preference", () => {
  test("reports whether this terminal can actually send Rex status", () => {
    expect(reportingIssue(true, true, { REX_BLOCK: "block", TERM: "xterm-256color" })).toBeUndefined();
    expect(reportingIssue(false, true, { REX_BLOCK: "block" })).toBe("no interactive TTY");
    expect(reportingIssue(true, true, {})).toBe("not inside Rex");
    expect(reportingIssue(true, true, { REX_BLOCK: "block", TERM: "screen-256color" })).toBe("tmux/screen is not supported");
    expect(reportingIssue(true, true, { REX_BLOCK: "block", PI_PROGRAM_STATUS: "0" })).toBe("PI_PROGRAM_STATUS=0");
  });

  test("defaults on, respects the switch and fails closed for invalid files", () => {
    const directory = mkdtempSync(join(tmpdir(), "pulau-pi-config-test-"));
    const path = join(directory, "plugin.json");
    try {
      expect(readGlobalEnabled(path)).toBe(true);
      writeFileSync(path, '{"enabled":false}');
      expect(readGlobalEnabled(path)).toBe(false);
      writeFileSync(path, '{"enabled":true,"future":"preserved"}');
      expect(readGlobalEnabled(path)).toBe(true);
      writeFileSync(path, '{"enabled":"false"}');
      expect(readGlobalEnabled(path)).toBe(false);
      writeFileSync(path, "{");
      expect(readGlobalEnabled(path)).toBe(false);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

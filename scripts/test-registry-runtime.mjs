import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const temporary = mkdtempSync(resolve(tmpdir(), "xspoon-registry-reader-"));
const path = resolve(temporary, "xspoon_registry.json");
const payload = (id, bundleID, key) => ({ id, name: id, variant: "local", template: "single", semanticAction: id,
  appBundleID: bundleID, axRole: "AXButton", axDescription: "Fixture control", replayIntent: "physicalClick",
  hotkey: { modifiers: ["alt", "cmd"], key } });

function read() {
  const lua = `local reader=dofile(${JSON.stringify(resolve(root, "assets/hammerspoon/scripts/browser_automations.lua"))}); local actions,info=reader.readElementActions(${JSON.stringify(path)}); local ids={}; for _,a in ipairs(actions) do table.insert(ids,a.id) end; table.sort(ids); return hs.json.encode({ids=ids,info=info})`;
  const script = `tell application "Hammerspoon" to execute lua code "${lua.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
  return JSON.parse(execFileSync("/usr/bin/osascript", ["-e", script], { encoding: "utf8", timeout: 10000 }).trim());
}

try {
  const registry = { schemaVersion: 1, apps: [{ id: "fixture", name: "Fixture", bundleIdentifier: "test.fixture", icon: "app", actions: [
    { payload: payload("canonical-working", "test.fixture", "s"), origin: "capture", review: { state: "verified", reason: "Fixture" } },
    { payload: payload("old-blocked", "test.fixture", "e"), origin: "capture", review: { state: "blocked", reason: "Conflict" } },
    { legacyShortcut: { id: "inherited", action: "Legacy", key: "M", modifierID: "right-command" }, origin: "legacyCommand", review: { state: "inherited", reason: "External script" } },
  ] }] };
  writeFileSync(path, JSON.stringify(registry));
  const valid = read();
  assert.deepEqual(valid.ids, ["canonical-working"]);
  assert.equal(valid.info.source, "canonical");
  registry.apps[0].actions[0].payload.appBundleID = "wrong.parent";
  writeFileSync(path, JSON.stringify(registry));
  const invalid = read();
  assert.equal(Object.keys(invalid.ids).length, 0);
  assert.match(invalid.info.error, /parent/i);
  writeFileSync(path, "not-json");
  const malformed = read();
  assert.equal(Object.keys(malformed.ids).length, 0);
  assert.ok(malformed.info.error);
  for (const apps of [
    [42],
    [{ bundleIdentifier: "test.fixture", actions: [42] }],
    [{ bundleIdentifier: "test.fixture", actions: [{ payload: 42 }] }],
    [{ bundleIdentifier: "test.fixture", actions: [{ payload: payload("bad-review", "test.fixture", "s"), origin: "capture", review: 42 }] }],
  ]) {
    writeFileSync(path, JSON.stringify({ schemaVersion: 1, apps }));
    const scalar = read();
    assert.equal(Object.keys(scalar.ids).length, 0);
    assert.ok(scalar.info.error, "Malformed entries must return a readable error, not throw");
  }
  console.log("PASS: Hammerspoon reads the canonical registry, skips blocked/inherited entries, and fails closed on invalid data. No actions executed.");
} finally {
  rmSync(temporary, { recursive: true, force: true });
}

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const temporary = mkdtempSync(resolve(tmpdir(), "xspoon-registry-reader-"));
const path = resolve(temporary, "xspoon_registry.json");
const payload = (id, bundleID, key) => ({ id, name: id, variant: "local", template: "single", semanticAction: id,
  appBundleID: bundleID, axRole: "AXButton", axDescription: "Fixture control", replayIntent: "physicalClick",
  hotkey: { modifiers: ["alt", "cmd"], key } });

function read(checkSuppression = false) {
  const query = checkSuppression ? `,suppression={deleted=reader.isLegacyShortcutDisabled("test.fixture",{"ctrl","alt"},"s",${JSON.stringify(path)}),otherApp=reader.isLegacyShortcutDisabled("test.other",{"ctrl","alt"},"s",${JSON.stringify(path)}),otherKey=reader.isLegacyShortcutDisabled("test.fixture",{"ctrl","alt"},"d",${JSON.stringify(path)})}` : "";
  const lua = `local reader=dofile(${JSON.stringify(resolve(root, "assets/hammerspoon/scripts/browser_automations.lua"))}); local actions,info=reader.readElementActions(${JSON.stringify(path)}); local ids={}; for _,a in ipairs(actions) do table.insert(ids,a.id) end; table.sort(ids); return hs.json.encode({ids=ids,info=info${query}})`;
  return executeLua(lua);
}

function executeLua(lua) {
  const script = `tell application "Hammerspoon" to execute lua code "${lua.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
  return JSON.parse(execFileSync("/usr/bin/osascript", ["-e", script], { encoding: "utf8", timeout: 10000 }).trim());
}

function readDefault() {
  return executeLua(`local proxy=setmetatable({configdir=${JSON.stringify(temporary)}},{__index=hs}); local env=setmetatable({hs=proxy},{__index=_G}); local reader=assert(loadfile(${JSON.stringify(resolve(root, "assets/hammerspoon/scripts/browser_automations.lua"))},"t",env))(); local actions,info=reader.readElementActions(); local ids={}; for _,a in ipairs(actions) do table.insert(ids,a.id) end; return hs.json.encode({ids=ids,info=info,blocked=reader.isLegacyShortcutDisabled("test.fixture",{"alt","ctrl"},"s")})`);
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
  registry.disabledLegacyShortcuts = [{ id: "deleted-search", appBundleID: "test.fixture", modifiers: ["alt", "ctrl"], key: "s" }];
  writeFileSync(path, JSON.stringify(registry));
  const suppressed = read(true);
  assert.deepEqual(suppressed.suppression, { deleted: true, otherApp: false, otherKey: false });
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
  writeFileSync(resolve(temporary, "browser_element_actions.json"), JSON.stringify([payload("must-not-fall-back", "test.fixture", "s")]));
  writeFileSync(path, JSON.stringify({ schemaVersion: 1, apps: [], disabledLegacyShortcuts: registry.disabledLegacyShortcuts }));
  chmodSync(path, 0o000);
  try {
    const unreadable = readDefault();
    assert.equal(Object.keys(unreadable.ids).length, 0, "Unreadable canonical data must not fall back to old actions");
    assert.equal(unreadable.info.source, "canonical");
    assert.ok(unreadable.info.error);
    assert.equal(unreadable.blocked, true, "Deleted routes must fail closed when policy is unreadable");
  } finally {
    chmodSync(path, 0o600);
  }
  rmSync(path);
  const absent = readDefault();
  assert.deepEqual(absent.ids, ["must-not-fall-back"], "Pre-migration fallback is allowed only when canonical data is absent");
  assert.equal(absent.info.source, "legacy");
  console.log("PASS: canonical registry, deletion guards, malformed/unreadable fail-closed behavior, and absent-only legacy fallback. No actions executed.");
} finally {
  rmSync(temporary, { recursive: true, force: true });
}

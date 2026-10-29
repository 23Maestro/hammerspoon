import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const script = resolve(dirname(fileURLToPath(import.meta.url)), "modifier-ledger.mjs");

test("modifier lookup reads selected config, preserves conditions, and rejects drift", () => {
  const directory = mkdtempSync(resolve(tmpdir(), "xspoon-modifier-ledger-"));
  try {
    const bin = resolve(directory, "scripts/modifier-ledger.mjs");
    const config = resolve(directory, ".config/karabiner/karabiner.json");
    mkdirSync(dirname(bin), { recursive: true });
    mkdirSync(dirname(config), { recursive: true });
    copyFileSync(script, bin);
    const profile = {
      name: "Fixture", selected: true,
      complex_modifications: { rules: [
        { description: "Fixture override", manipulators: [{ from: { key_code: "right_shift" }, conditions: [{ type: "variable_if", name: "mode", value: 1 }], to: [{ key_code: "escape" }] }] },
        { description: "Right Shift", manipulators: [{ type: "basic", from: { key_code: "right_shift" }, to: [{ key_code: "left_option", modifiers: ["left_command"] }] }] },
      ] },
    };
    const save = () => writeFileSync(config, JSON.stringify({ profiles: [profile] }));
    const run = (...args) => spawnSync(process.execPath, [bin, ...args], { env: { ...process.env, HOME: directory }, encoding: "utf8" });
    save();
    assert.equal(run("refresh").status, 0);
    const lookup = run("lookup", "right shift");
    assert.equal(lookup.status, 0, lookup.stderr);
    const entry = JSON.parse(lookup.stdout);
    assert.deepEqual(entry.hammerspoonModifiers, ["alt", "cmd"]);
    assert.equal(entry.source.profile, "Fixture");
    assert.deepEqual(entry.earlierSameKeyRules[0].conditions, [{ type: "variable_if", name: "mode", value: 1 }]);
    assert.equal(entry.verification.physicalKeypress, "not-tested");
    assert.equal(run("lookup", "right_control").status, 1);

    profile.complex_modifications.rules[1].manipulators[0].to[0].modifiers = ["left_control"];
    save();
    const stale = run("lookup", "right shift");
    assert.equal(stale.status, 1);
    assert.match(stale.stderr, /stale or altered/);
    assert.equal(run("refresh").status, 0);
    const refreshed = run("lookup", "right shift");
    assert.equal(refreshed.status, 0, refreshed.stderr);
    assert.deepEqual(JSON.parse(refreshed.stdout).hammerspoonModifiers, ["alt", "ctrl"]);
    assert.equal(run("check").status, 0);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, renameSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ledgerPath = resolve(root, "assets/hammerspoon/registry/modifier-ledger.jsonl");
const sourcePath = resolve(homedir(), ".config/karabiner/karabiner.json");
const modifierNames = new Map([
  ["left_command", "cmd"], ["right_command", "cmd"],
  ["left_option", "alt"], ["right_option", "alt"],
  ["left_control", "ctrl"], ["right_control", "ctrl"],
  ["left_shift", "shift"], ["right_shift", "shift"],
  ["command", "cmd"], ["option", "alt"], ["control", "ctrl"], ["shift", "shift"],
]);
const names = {
  caps_lock: ["Hyper", "caps lock", "hyper key"],
  right_command: ["Right Command", "right cmd", "r cmd", "right command mod"],
  right_shift: ["Right Shift", "r shift", "r shft", "right shift mod"],
  right_option: ["Right Option", "right alt", "r opt", "r option"],
  grave_accent_and_tilde: ["Tilde", "grave", "backtick", "tilde mod"],
  open_bracket: ["Left Bracket", "open bracket", "l brkt", "["],
  close_bracket: ["Right Bracket", "close bracket", "r brkt", "]"],
  backslash: ["Backslash", "backslash hold", "\\"],
  tab: ["Tab", "tab hold"],
  left_control: ["Left Control", "left ctrl", "l ctrl"],
};
const normalize = (name) => name.toLowerCase().trim().replace(/[_-]/g, " ").replace(/\s+/g, " ");
const digest = (data) => createHash("sha256").update(data).digest("hex");

function selectedSource() {
  const bytes = readFileSync(sourcePath);
  const config = JSON.parse(bytes);
  const profiles = config.profiles.map((profile, index) => ({ profile, index })).filter(({ profile }) => profile.selected);
  if (profiles.length !== 1) throw new Error("Expected exactly one selected Karabiner profile");
  return { ...profiles[0], sha256: digest(bytes) };
}

function buildRecords() {
  const { profile, index, sha256 } = selectedSource();
  const prior = [];
  const records = [];
  for (const [ruleIndex, rule] of (profile.complex_modifications?.rules ?? []).entries()) {
    for (const [manipulatorIndex, manipulator] of (rule.manipulators ?? []).entries()) {
      const key = manipulator.from?.key_code;
      const pointer = `/profiles/${index}/complex_modifications/rules/${ruleIndex}/manipulators/${manipulatorIndex}`;
      const outputPhase = ["to", "to_if_held_down"].find((phase) =>
        manipulator[phase]?.some((event) => modifierNames.has(event.key_code)) &&
        manipulator[phase].every((event) => modifierNames.has(event.key_code) || event.set_variable));
      if (key && outputPhase) {
        const mandatory = manipulator.from.modifiers?.mandatory ?? [];
        const output = manipulator[outputPhase];
        const flags = [...new Set([...mandatory, ...output.flatMap((event) =>
          event.key_code ? [event.key_code, ...(event.modifiers ?? [])] : [])]
          .map((name) => modifierNames.get(name)).filter(Boolean))].sort();
        const [baseLabel = key, ...aliases] = names[key] ?? [];
        const qualifier = mandatory.length ? ` with ${mandatory.join(" + ")}` : "";
        const label = baseLabel + qualifier;
        const earlierRules = prior.filter((entry) => entry.from.key_code === key || entry.from.any === "key_code");
        records.push({
          schemaVersion: 1,
          id: `${key}${mandatory.length ? "--" + mandatory.join("-") : ""}`,
          label,
          aliases: [label, ...(mandatory.length ? [] : aliases)],
          evidence: "selected-profile-config",
          verification: { config: "verified", physicalKeypress: "not-tested", actionReplay: "not-tested" },
          source: { path: sourcePath, sha256, profile: profile.name, profileIndex: index, pointer, ruleDescription: rule.description },
          physicalInput: manipulator.from,
          outputPhase,
          outputEvents: output,
          hammerspoonModifiers: flags,
          tapEvents: manipulator.to_if_alone ?? [],
          keyUpEvents: manipulator.to_after_key_up ?? [],
          conditions: manipulator.conditions ?? [],
          parameters: manipulator.parameters ?? {},
          earlierSameKeyRules: earlierRules,
          runtimeOwner: "Hammerspoon for XSpoon actions",
          notes: [
            "This records physical translation, not an app action binding.",
            ...(earlierRules.length ? ["Earlier rules may consume this physical key in their conditions; order is preserved below."] : []),
          ],
        });
      }
      if (key || manipulator.from?.any) {
        prior.push({ pointer, description: rule.description, from: manipulator.from, conditions: manipulator.conditions ?? [], to: manipulator.to ?? [] });
      }
    }
  }
  if (!records.length) throw new Error("No custom modifier records found");
  return records;
}

function checkedRecords() {
  const rows = readFileSync(ledgerPath, "utf8").trim().split("\n").map((line) => JSON.parse(line));
  const expected = buildRecords();
  if (JSON.stringify(rows) !== JSON.stringify(expected)) {
    throw new Error("Modifier ledger is stale or altered. Review the selected profile, then run: node scripts/modifier-ledger.mjs refresh");
  }
  return rows;
}

try {
  const [command = "check", ...args] = process.argv.slice(2);
  if (command === "refresh") {
    const rows = buildRecords();
    mkdirSync(dirname(ledgerPath), { recursive: true });
    writeFileSync(ledgerPath + ".tmp", rows.map((row) => JSON.stringify(row)).join("\n") + "\n");
    renameSync(ledgerPath + ".tmp", ledgerPath);
    console.log(JSON.stringify({ status: "refreshed", records: rows.length, path: ledgerPath }));
  } else if (command === "check") {
    const rows = checkedRecords();
    console.log(JSON.stringify({ status: "current", records: rows.length, profile: rows[0].source.profile, sourceSHA256: rows[0].source.sha256 }));
  } else if (command === "lookup") {
    const query = normalize(args.join(" "));
    if (!query) throw new Error("Supply a modifier name, for example: lookup 'right shift'");
    const rows = checkedRecords();
    const matches = rows.filter((row) => [row.id, ...row.aliases].some((name) => normalize(name) === query));
    if (matches.length !== 1) throw new Error(`No unique configured modifier named '${args.join(" ")}'. Right Control is not a configured alias for Right Option.`);
    console.log(JSON.stringify(matches[0], null, 2));
  } else {
    throw new Error("Usage: node scripts/modifier-ledger.mjs check | refresh | lookup <name>");
  }
} catch (error) {
  console.error(JSON.stringify({ status: "error", message: error.message }));
  process.exitCode = 1;
}

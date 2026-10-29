# Modifier Ledger

`modifier-ledger.jsonl` is the canonical lookup record for Jerami's configured
physical modifier presets. One line describes one modifier rule in the selected
Karabiner profile. Never infer the emitted chord from its label or a July note.

```sh
node scripts/modifier-ledger.mjs lookup "right shift"
node scripts/modifier-ledger.mjs check
```

Both commands verify the ledger against the current selected profile and source
SHA-256. A stale ledger fails rather than returning an outdated answer. After
reviewing an intentional config change, regenerate it:

```sh
node scripts/modifier-ledger.mjs refresh
```

The command only reads the live Karabiner config. It never writes remaps, runs a
macro, changes profiles, or reloads an app. Preserve rule order, input modifier
requirements, tap behavior, timing, conditions, and earlier same-key rules when
reasoning about a preset. Earlier rules are possible overrides, not proof that
their conditions are currently active.

Configuration verification is not a physical keypress test or an action replay
test. Each record states that distinction. A physical remap and an app-scoped
Hammerspoon action are different things. Hammerspoon remains XSpoon's action
engine; this ledger does not introduce a second action engine.

Right Control is not configured as a custom modifier in the selected profile.
Do not treat the old XSpoon `R CTRL/OPT` label as evidence that it is.

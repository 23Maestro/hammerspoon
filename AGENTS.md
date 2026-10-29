# XSpoon Recovery

Read [CONTEXT.md](./CONTEXT.md) for domain terms and [the modifier ledger](./assets/hammerspoon/registry/README.md) before interpreting physical modifier names. Use `node scripts/modifier-ledger.mjs lookup "right shift"`; never guess from UI labels. A stale lookup must be refreshed from reviewed live configuration.

Keep Hammerspoon as the app-action runtime and XSpoon as the capture/catalog UI. Existing Karabiner remaps translate physical keys; do not add an action workaround without a documented Hammerspoon limitation. Keep old findings separate from current runtime proof.

Saved captures use `~/.hammerspoon/xspoon_registry.json`, organized as App -> Actions. Do not write the old UserDefaults catalog or `browser_element_actions.json` as parallel stores. See [the migration receipt](./docs/2026-10-29-per-app-registry.md). Leave the verified System Settings Right Shift+S action unchanged and do not retest it without a new user-reported failure.

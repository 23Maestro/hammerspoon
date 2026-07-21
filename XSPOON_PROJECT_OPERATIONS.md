# XSpoon Project Operations

## Source Of Truth

- GitHub repository: https://github.com/23Maestro/hammerspoon
- Git remote: `https://github.com/23Maestro/hammerspoon.git`
- Linear project: https://linear.app/23maestro/project/xspoon-081b087ce006
- Linear team: `23Maestro`

## Access Checks

```sh
gh auth status
gh api repos/23Maestro/hammerspoon
```

The local GitHub CLI is `/opt/homebrew/bin/gh`, authenticated as `23Maestro`. The repository is public so the GitHub connector can access it directly. Do not write tokens or auth output into the repository.

## Ownership

- GitHub owns the durable map, research, implementation tickets, and PR history.
- Linear owns the mobile decision cockpit and links back to GitHub.
- `gh` is the fallback for GitHub operations if the connector is unavailable.
- Hammerspoon remains the runtime source of truth for automation behavior.
- XSpoon app changes are not separate from this repository. When behavior crosses the app/runtime boundary, commit and push the Swift and Lua changes together.

## Push Checklist

Before pushing XSpoon work:

```sh
git status --short
git diff -- apps/XSpoon assets/hammerspoon README.md XSPOON_PROJECT_OPERATIONS.md
```

Use extension-only pushes only when the diff is limited to the Raycast extension surface. If `apps/XSpoon` or `assets/hammerspoon` changed, call that out in the commit message and PR/branch summary.

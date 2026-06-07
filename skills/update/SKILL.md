---
name: cordon-update
description: Update this project's Cordon installation to the latest release — compare versions, re-run the installer, commit the result, and verify with the doctor. Human-invoked only, because it rewrites the governance itself.
disable-model-invocation: true
allowed-tools: Bash(git clone *), Bash(git add *), Bash(git commit *), Bash(git status *), Bash(git rev-parse *), Bash(rm -r .cordon-update-tmp*), WebFetch(domain:raw.githubusercontent.com)
---

# Cordon — update

The human asked to update Cordon. Updating rewrites `.claude/` — the
project's own governance — so every consequential step below is shown to
and approved by the human. Never improvise around a blocked step.

## 1. Compare versions

- Installed: read `CORDON_VERSION` from `.claude/cordon.config` in the
  **main checkout** (find it via `git rev-parse --git-common-dir`, stripping
  the trailing `/.git`). Older installs may have no version line — treat as
  "pre-0.2.0, update recommended".
- Latest: WebFetch
  `https://raw.githubusercontent.com/ggoosen/Cordon/main/.claude-plugin/plugin.json`
  and read `.version`.

If they match, say so and stop. Otherwise show both versions and confirm
the human wants to proceed.

## 2. Fetch and install

From the main checkout root:

```
git clone --depth 1 https://github.com/ggoosen/Cordon.git .cordon-update-tmp
bash .cordon-update-tmp/install.sh .
rm -r .cordon-update-tmp
```

Notes:
- The clone goes *inside* the workspace (`.cordon-update-tmp`) so the
  sandbox allows it; approve the `github.com` network prompt if asked.
- The installer preserves the project's existing posture and policy.
- Writing `.claude/settings.json` is protected by the sandbox, so the
  install step may need to run unsandboxed — Claude Code will ask the human
  to approve that. That approval IS the deliberate human act of changing
  policy; explain it rather than working around it.
- If the install step stays blocked, hand it to the human instead: tell
  them to type `! bash .cordon-update-tmp/install.sh .` (the `!` prefix runs
  it directly in their shell), or the one-liner from their own terminal:
  `curl -fsSL https://raw.githubusercontent.com/ggoosen/Cordon/main/install.sh | bash`

## 3. Commit and verify

```
git add CLAUDE.md .claude .gitignore
git commit -m "update cordon to <version>"
bash .claude/cordon-doctor.sh
```

Report the doctor's verdict.

## 4. Remind about worktrees

Existing worktrees are checkouts of older commits and keep the OLD rails
until refreshed. Recommend: finish or discard current worktree sessions,
then start fresh ones with `claude --worktree` (or run `git merge` from the
updated base inside a worktree that must live on).

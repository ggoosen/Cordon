---
name: cordon-status
description: Show where this Cordon session stands — isolation state, policy, what's changed, what's been blocked, and the sanctioned next step. Use when the user asks where things are at, or seems lost in the workflow.
allowed-tools: Bash(git status *), Bash(git branch *), Bash(git diff *), Bash(git log *), Bash(git rev-parse *), Bash(git worktree *), Bash(tail *), Bash(wc *)
---

# Cordon — status

Give the human a compact, honest picture of the session.

## Current state

(These injected commands must stay simple — no pipes, `$()`, or `||`, which
the permission layer refuses to analyze. Gather anything fancier yourself
in the steps below.)

- Branch: !`git branch --show-current`
- Checkout root: !`git rev-parse --show-toplevel`
- Linked worktrees: !`git worktree list`
- Changes: !`git status --short`
- Recent commits: !`git log --oneline -10`

Gather the rest yourself before reporting:
- **Diffstat vs base**: compute the base (`git merge-base HEAD origin/HEAD`,
  falling back to `main`, then `master`), then `git diff --stat <base>..HEAD`.
- **Policy**: Read `.claude/cordon.config` (in the MAIN checkout — find it
  via `git rev-parse --git-common-dir`, stripping the trailing `/.git`).
- **Blocked attempts**: `tail -10` the main checkout's
  `.claude/cordon-audit.jsonl` if it exists; entries with
  `"event":"PreToolUse-denied"` are blocks.

## Report

1. **Where am I?** One line: isolated worktree (name, branch) or — loudly —
   the un-isolated main checkout, plus the active policy.
2. **What's changed?** Files touched, commits made this session, anything
   uncommitted.
3. **What's been blocked?** If the user hit denials recently, explain which
   Cordon rule fired and why it exists (check the audit log for context).
4. **What's next?** The sanctioned step: keep working, `/cordon-review` when
   ready, then the human chooses `/cordon-accept` or `/cordon-discard`. If
   not isolated, the next step is entering a worktree (offer EnterWorktree
   or `claude --worktree`).

Keep it under a screen. No lecture — state, then next step.

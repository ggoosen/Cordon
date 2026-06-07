---
name: cordon-discard
description: Throw away this isolated session entirely — delete the worktree and its branch. Use when the work is not wanted (or after /cordon-accept has landed it). Irreversible, but only affects the throwaway worktree.
disable-model-invocation: true
allowed-tools: Bash(git worktree *), Bash(git branch *), Bash(git rev-parse *), Bash(git status *), Bash(git log *)
---

# Cordon — discard

The human has decided to throw this worktree away. Make sure they know what
they're throwing away, then remove it cleanly.

1. **Name what is about to be removed**: the worktree path (`git rev-parse
   --show-toplevel`), its branch (`git branch --show-current`), how many
   commits it holds beyond the base, and whether there are uncommitted
   changes (`git status --short`). If a `cordon-accepted/*` branch was
   created from this HEAD, say the work is already safe there.
2. **Ask the human to confirm** with a clear summary ("delete worktree X and
   branch Y, discarding N commits and M uncommitted files?"). Wait for an
   explicit yes.
3. **Remove it** from the main checkout's perspective:
   ```
   git -C <main-checkout-root> worktree remove --force <worktree-path>
   git -C <main-checkout-root> branch -D <worktree-branch>
   ```
   Find the main checkout root via `git rev-parse --git-common-dir` (strip
   the trailing `/.git`). If git refuses because this session's cwd is
   inside the worktree being removed, print those exact commands and tell
   the human to run them after exiting this session — exiting a clean
   worktree session also triggers Claude Code's own cleanup prompt.
4. **Confirm the main checkout is untouched**: `git -C <main-root> status
   --short` should show no changes caused by the removal.

Never discard without the explicit confirmation in step 2. Never touch any
branch other than this worktree's own `worktree-*` branch.

---
name: cordon-accept
description: Land the reviewed work from this worktree onto a fresh, named review branch off the base — never onto main, never via push. Use only after /cordon-review.
disable-model-invocation: true
allowed-tools: Bash(git status *), Bash(git branch *), Bash(git log *), Bash(git rev-parse *), Bash(git merge-base *)
---

# Cordon — accept (land to a fresh branch)

The human has decided this work should land. Your job is to make it
land *safely*: on a fresh branch, never on main, never pushed.

1. **Confirm the worktree is clean-committed.** Run `git status --porcelain`;
   if there are uncommitted changes or untracked files, stop and tell the
   human to commit (or discard) them first. Do not auto-commit.
2. **Name the landing branch**: `cordon-accepted/<worktree-name>-<shortsha>`,
   where `<worktree-name>` is the basename of this worktree's directory and
   `<shortsha>` is `git rev-parse --short HEAD`.
3. **Create it at the current HEAD**: `git branch <name> HEAD`. The worktree
   branch already contains exactly the session's commits on top of the base,
   so pointing a new branch at HEAD lands them without any cherry-picking.
   (Branches are shared across worktrees — the branch is immediately visible
   in the main checkout.)
4. **Hand over.** Print the branch name and the exact commands the human can
   run from their main checkout to take it from here, e.g.:
   ```
   git merge --no-ff cordon-accepted/<...>     # merge locally, or
   git push -u origin cordon-accepted/<...>    # push and open a PR
   ```
   Then suggest `/cordon-discard` to clean up this worktree (the work is now
   safe on the accepted branch, so discarding the worktree loses nothing).

Do NOT push. Do NOT merge into main. Do NOT delete anything. Landing on a
shared remote or main is the human's final, deliberate act — Cordon's entire
design ends at handing them a clean branch.

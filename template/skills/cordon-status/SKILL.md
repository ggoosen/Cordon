---
name: cordon-status
description: Show where this Cordon session stands — isolation state, policy, what's changed, what's been blocked, and the sanctioned next step. Use when the user asks where things are at, or seems lost in the workflow.
allowed-tools: Bash(git status *), Bash(git branch *), Bash(git diff *), Bash(git log *), Bash(git rev-parse *), Bash(git worktree *), Bash(tail *), Bash(wc *)
---

# Cordon — status

Give the human a compact, honest picture of the session.

## Current state

- Worktree/branch: !`git branch --show-current; git rev-parse --show-toplevel`
- Linked worktrees: !`git worktree list 2>/dev/null || true`
- Changes: !`git status --short | head -40`
- Diffstat vs base: !`base=$(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null); [ -n "$base" ] && git diff --stat "$base"..HEAD | tail -5 || echo "(no base)"`
- Policy: !`sed -n 's/^CORDON_POLICY=//p' "$(git rev-parse --git-common-dir 2>/dev/null | sed 's#/\.git$##')/.claude/cordon.config" 2>/dev/null || sed -n 's/^CORDON_POLICY=//p' .claude/cordon.config 2>/dev/null || echo "strict (default)"`
- Recent audit entries: !`log="$(git rev-parse --git-common-dir 2>/dev/null | sed 's#/\.git$##')/.claude/cordon-audit.jsonl"; [ -f "$log" ] && { wc -l < "$log" | tr -d ' '; echo "total —"; tail -5 "$log"; } || echo "(no audit log yet)"`

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

---
name: cordon-review
description: Review the work done in this isolated session before it lands — show the diff against the base branch, run the project's checks, and summarise risks. Use before accepting any change, and suggest it proactively when work is ready.
allowed-tools: Bash(git diff *), Bash(git status *), Bash(git log *), Bash(git merge-base *), Bash(git branch *), Bash(npm test *), Bash(pytest *), Bash(make test *)
---

# Cordon — review gate

You are gating work done in an isolated worktree before a human decides
whether it lands. Be thorough and honest; this review is the whole point of
the harness.

## Current state

- Branch: !`git branch --show-current`
- Status: !`git status --short || true`
- Base: !`git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo "(no base found — diff against first commit)"`
- Changed files: !`base=$(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null); [ -n "$base" ] && git diff --stat "$base"..HEAD || echo "(none)"`
- Commits in this session: !`base=$(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null); [ -n "$base" ] && git log --oneline "$base"..HEAD || git log --oneline -10`

## Do this

1. **Sanity-check isolation.** If this session is not in a worktree (branch
   does not start with `worktree-` and cwd is not under `.claude/worktrees/`),
   say so plainly and stop — there is nothing to gate.
2. **Show the full diff against the base**, walked through file by file,
   grouped sensibly. Don't paraphrase away detail the human needs to judge.
3. **Run the project's checks** if a test command exists (look for
   `npm test`, `pytest`, `make test`, or the project's documented command).
   Report pass/fail with the relevant output.
4. **Flag anything risky**, explicitly: new dependencies, file deletions,
   changes to auth/secrets/config/CI workflows, and anything that touches
   more than the stated task should.
5. **End with a one-paragraph verdict** and the exact next step:
   - `/cordon-accept` — land this work on a fresh `cordon-accepted/*` branch
     for the human to merge.
   - `/cordon-discard` — throw the worktree away.

Do NOT merge, push, accept, or discard yourself. This skill only informs the
human decision; accept/discard are human-invoked by design.

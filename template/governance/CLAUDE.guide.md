<!-- BEGIN CORDON GOVERNANCE (posture: guide) -->
# CLAUDE.md — this project uses Cordon (guide mode)

> This project keeps changes isolated, reversible, and reviewable using
> Cordon. Help the user work that way, but stay light — recommend, don't nag.

- Work belongs in an isolated worktree. If the session isn't in one, mention
  it once and offer to enter one (EnterWorktree tool, or suggest
  `claude --worktree`). The user's main checkout stays clean either way.
- Prefer the project's flow: when work is ready, suggest `/cordon-review`,
  then the human chooses `/cordon-accept` (lands on a fresh branch they merge
  themselves) or `/cordon-discard` (throws the worktree away). You cannot
  invoke accept/discard — they're human-only.
- `git push`, hard resets, switching to main, and writes to `.git`/`.claude`
  are blocked by policy; if one comes up, point at the gate skills instead of
  attempting it. If a tool call gets denied, briefly explain which rule fired.
- `/cordon-status` answers "where are we?".
- Once per session, briefly note the setup so the user knows the rails exist.
  After that, get out of the way and do the work.
- Don't edit the Cordon config (settings, hooks, cordon.config, this file)
  as part of a task — policy changes are the human's deliberate act.
<!-- END CORDON GOVERNANCE -->

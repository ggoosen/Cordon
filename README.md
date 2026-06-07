# Cordon

**Every Claude Code session in your repo becomes isolated, sandboxed, and
diff-gated — using nothing but Claude Code's own primitives.**

A cordon forces everything through one controlled boundary. Install Cordon
into a project and every session there is pushed into the same flow:

```
work happens in a throwaway git worktree        (never your checkout)
  → inside the OS sandbox + a boundary hook     (never outside the workspace)
    → reviewed at a human gate (/cordon-review) (never silently)
      → landed on a fresh branch you merge      (never pushed, never to main)
        → or discarded without a trace
```

> ## ⚠️ The honest security line — read this first
>
> Claude Code's sandbox is OS-level sandboxing of the **Bash tool** — real,
> but Anthropic explicitly does **not** position it as a trust boundary
> against hostile code. There is no separate kernel. **Cordon's job is to
> make the safe, reversible, reviewable workflow the path of least
> resistance — not to contain an adversary.** It protects you from accidents
> and agent misbehavior: the wrong-directory edit, the overeager
> `git push`, the "helpful" hard reset. If you're running code or agents you
> actively distrust, you want container/VM isolation — see
> [Sandkeep](https://github.com/ggoosen/Sandkeep), Cordon's Docker-engined
> sibling ([more below](#relationship-to-sandkeep)).
> The full list of limits is in [Honest limitations](#honest-limitations).

## Quick start

```bash
# in your project (must be a git repo):
curl -fsSL https://raw.githubusercontent.com/ggoosen/Cordon/main/install.sh | bash

# or from a clone:
git clone https://github.com/ggoosen/Cordon.git
./Cordon/install.sh /path/to/your/project
```

Then commit the new files (`CLAUDE.md`, `.claude/`, `.gitignore`) and start
an isolated session:

```bash
claude --worktree
```

Work normally. When the work is ready: `/cordon-review` → you decide:
`/cordon-accept` (lands a `cordon-accepted/*` branch for you to merge or
push) or `/cordon-discard` (deletes the worktree, your checkout untouched).

Requirements: git, **jq** (the hooks fail closed without it), Claude Code
≥ 2.1.x. Sandbox: macOS (built-in Seatbelt) or Linux/WSL2
(`apt install bubblewrap socat`).

## What you get

| Guarantee | Mechanism |
|---|---|
| **G0** The agent understands the method and shepherds you through it | `CLAUDE.md` governance brain — narrates state, explains blocks, refuses-and-redirects |
| **G1** Work is isolated from your branch/tree | `claude --worktree` → throwaway branch under `.claude/worktrees/` |
| **G2** The agent can't touch the host outside its workspace | OS sandbox (Seatbelt/bubblewrap) + a `PreToolUse` boundary hook |
| **G3** The escape hatches are closed | `permissions.deny`: no push, no hard reset, no `.git`/`.claude` writes, no secret reads, no raw `curl` |
| **G4** Nothing lands without human review | `/cordon-review` gate; accept/discard are **human-only** (`disable-model-invocation`) |
| **G5** Everything is logged | JSON-lines audit trail in `.claude/cordon-audit.jsonl` (written to the main checkout, survives discards) |

Inside the boundary, sessions feel *more* autonomous, not less: sandboxed
Bash auto-runs without permission prompts, because the OS boundary — not a
prompt — is what contains it.

### Two postures, two policies

- **Posture** (`install.sh --posture`) sets the governance *voice* in
  CLAUDE.md: `enforce` (default — refuses out-of-flow requests, narrates
  every block) or `guide` (recommends, stays out of the way).
- **Policy** (`install.sh --policy`, or `CORDON_POLICY`) sets the *hard*
  rule: `strict` (default — file edits outside an isolated worktree are
  **denied** by the boundary hook) or `guided` (warn but allow main-checkout
  work; protections on `.git`/`.claude`/escape-hatches stay on).

## How the enforcement layers stack

1. **Defaults** — committed `.claude/settings.json` puts every session in the
   right mode: sandbox on, deny rules active, hooks wired, statusline showing
   the real isolation state.
2. **Deny rules** — merge across scopes and cannot be loosened by a lower
   scope. Claude Code splits compound commands and checks each part, so
   `npm test && git push` is still caught.
3. **Hooks** — `boundary.sh` (PreToolUse) actively denies out-of-worktree
   writes, `.git`/`.claude` writes, raw network egress, `sudo`, recursive
   force-deletes — and **fails closed** on any internal error.
   `enforce-isolation.sh` (SessionStart) injects the session's isolation
   state as authoritative context. `audit.sh` (PostToolUse) writes the trail.
4. **Managed settings** *(optional)* — deploy
   [`managed-settings.example.json`](managed-settings.example.json) via
   MDM/admin and the rules become unoverridable, even by editing project
   files. This is the only truly "forced" tier; without it, Cordon governs
   the **agent** and assumes a cooperative human.

And underneath the hard layers, the soft one: **CLAUDE.md** makes Claude
*choose* the right path and explain the house to you — so you're shepherded
through a method, not bumping into fences. Soft and hard are deliberately
redundant: every security-relevant rule in CLAUDE.md also exists in deny
rules or hooks.

## Plugin install (skills + hooks only)

```
/plugin install ggoosen/Cordon
```

gives you `/cordon:review`, `/cordon:accept`, `/cordon:discard`,
`/cordon:status` and the hooks. **A plugin cannot ship the project's
`settings.json` (sandbox + deny rules) or the `CLAUDE.md` governance brain** —
those are project-scoped. The plugin is a convenience layer; **the template
install (`install.sh`) is the complete framework.** Don't let `/plugin
install` alone make you feel governed or sandboxed.

## Repo layout

```
template/          what install.sh places into your project (source of truth)
  CLAUDE.md governance (enforce/guide), settings.json, hooks/, skills/, statusline/
skills/, hooks/    the same logic at plugin scope (generated — scripts/sync-plugin.sh)
managed-settings.example.json   the admin-deployed, unoverridable tier
tests/             adversarial tests for the hooks + installer (+ opt-in LLM governance tests)
docs/              design spec, enforcement model, verified API surface
```

## Testing

```bash
./tests/run.sh                          # boundary + enforcement (fast, no API)
CORDON_RUN_LLM_TESTS=1 ./tests/run.sh   # + live governance behavior checks
```

`tests/test-boundary.sh` plays adversary against the boundary hook — path
traversal, symlinked parents, compound commands, word-boundary tricks —
and proves benign work passes.

## Honest limitations

- **Not a malicious-code boundary.** The sandbox contains accidents and
  misbehavior, not a determined adversary. The network proxy allowlists by
  hostname without TLS inspection (domain fronting is possible). For
  untrusted code, use a container/VM (Sandkeep).
- **macOS sandboxing rides on Seatbelt** (`sandbox-exec` plumbing Apple has
  deprecated but still ships and Claude Code still uses). The statusline
  reports *configured* sandbox state (`cfg-on`) — run `/sandbox` to see live
  state. Never let "off" read as "protected".
- **"Forced" only fully holds under managed settings.** Without admin
  deployment, a determined human can edit project settings. Cordon governs
  the agent and assumes a cooperative operator — that's the design centre.
- **No native always-worktree or diff-gate exists** (verified at CLI
  2.1.168; SessionStart hooks cannot block startup). Cordon builds both from
  hooks + skills. If Claude Code ships native equivalents, prefer them.
- **Hooks are bypassable by editing the hooks** — which is why the
  security-relevant rules also live in `permissions.deny` (merge-and-can't-
  loosen) and optionally managed settings. Defense in depth, not one check.
- **The boundary hook's Bash parsing is best-effort.** It catches the common
  escapes (and the deny rules catch compound forms), but a sufficiently
  creative shell one-liner can evade string matching — that's what the OS
  sandbox is for. Symlinked *leaf* files are likewise backstopped by the
  permission system's symlink checks and the sandbox, not the hook.
- **The governance layer is soft.** CLAUDE.md shapes what Claude chooses,
  not what it can do, and can drift in long sessions. Hooks/settings enforce;
  governance guides.

## Relationship to Sandkeep

Cordon and [**Sandkeep**](https://github.com/ggoosen/Sandkeep) are one
mental model — *isolate → review → gate*, `accept`/`discard`, a JSON-lines
audit trail — with two engines:

- **Cordon** (this repo): zero infra, pure Claude Code config. For *"I trust
  the agent; I want disciplined, reversible, reviewable work."*
- **[Sandkeep](https://github.com/ggoosen/Sandkeep)**: an external
  controller driving Docker/microVM isolation, host repo mounted read-only,
  only a patch comes back. For *"I don't trust this agent or this code."*

Start here; when the trust assumption breaks, move there. Two doors, one
house.

## License

Apache-2.0 — see [LICENSE](LICENSE).

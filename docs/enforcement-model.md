# The Cordon enforcement model

Cordon's governance has two faces designed together: a **soft layer that
shapes intent** and a **hard layer that enforces the boundary**. Neither is
sufficient alone; each exists to cover the other's failure mode.

## The soft layer — governance (G0)

**Lever 0: `CLAUDE.md`.** Auto-loaded into Claude's context every session
(and, because it's committed, into every worktree's session too). It makes
Claude:

1. **Know the house rules** — isolation, no push, no main, gate before landing.
2. **Narrate them** — one-line state at session start, an explanation when a
   rule fires, the sanctioned next step.
3. **Refuse-and-redirect** — decline out-of-flow requests *before* a hard
   rule has to fire, pointing at `/cordon-review` → `/cordon-accept`.

Properties to keep in mind:

- **Soft and probabilistic.** The model usually follows it and occasionally
  drifts (long sessions, post-compaction). That is *why* the hard layer
  exists. A security-relevant rule must never live only here.
- **It governs the agent, not the human.** It can't stop a user; it makes
  Claude guide them.
- **Posture is a knob**: `enforce` (strict voice, default) vs `guide`
  (light voice). `install.sh --posture` stamps the choice.

## The hard layer — enforcement (G1–G5)

Four levers, strongest last:

### Lever 1: Defaults (`template/settings.json`)

Committed project settings put every session in the right mode without
anyone remembering anything: sandbox on, deny rules active, hooks wired,
statusline surfacing the real isolation state. Defaults are the cheapest
enforcement: they make the right thing the zero-effort thing.

### Lever 2: Deny rules (`permissions.deny`)

Static rules evaluated before any prompt, merged across scopes — a lower
scope can never loosen them. Claude Code splits compound commands
(`&&`, `;`, `|`…) and requires each part to pass, and strips wrappers like
`timeout`, so the obvious smuggling routes are covered platform-side.
Blocked: `git push`, `git reset --hard`, checkout/switch to main/master,
`rm -rf`, `sudo`, `curl`/`wget`/`nc`, writes to `.git`/`.claude`, reads of
`.env`/keys/`~/.ssh`/`~/.aws`.

### Lever 3: Hooks (active, runtime)

- **`boundary.sh` (PreToolUse)** — the centerpiece. Receives every pending
  Bash/Edit/Write/NotebookEdit call and denies anything that would: leave
  the worktree (strict policy denies *all* edits when not isolated), touch
  `.git`/`.claude` (checked **relative to the boundary root** — an absolute
  check would false-positive on every file in a worktree, since worktrees
  live under `.claude/worktrees/`), reach the raw network, `sudo`,
  recursive-force-delete, or redirect output into `.git`/`.claude`.
  Path checks canonicalize through symlinked parents and lexically resolve
  `..` before comparing. The hook **fails closed**: any internal error
  exits 2 (block), because Claude Code treats other non-zero exits as
  non-blocking.
- **`enforce-isolation.sh` (SessionStart)** — verified reality: SessionStart
  hooks *cannot* halt startup (exit 2 only prints stderr). So this hook
  injects authoritative `additionalContext`: isolation state, policy, and —
  when un-isolated under strict — the instruction to isolate (EnterWorktree
  tool or `claude --worktree`) *before* attempting work the boundary hook
  would deny anyway.
- **`audit.sh` (PostToolUse)** — appends one truncated JSON line per tool
  use to `<main checkout>/.claude/cordon-audit.jsonl`. Written to the main
  checkout deliberately, so the trail survives a discarded worktree. Never
  blocks; logging failure must not break a session.

Hook-vs-permission ordering (verified): a blocking hook overrides *allow*
rules, and *deny* rules apply regardless of hook output — so the layers can
only tighten each other, never loosen.

### Lever 4: Managed settings (optional, unoverridable)

`managed-settings.example.json`, deployed by an admin/MDM to the OS-level
managed path, sits above project and user settings *and CLI flags*. Adds
`failIfUnavailable` (no silent sandbox-off) and
`allowUnsandboxedCommands: false` (no unsandboxed retry escape hatch), and
disables `bypassPermissions` mode. **This is the only tier a determined
user cannot edit away.** Caution: `allowManagedHooksOnly` would disable
Cordon's project hooks — only use it if you ship the hooks via a managed
source.

## The gate (G4) — why accept/discard are human-only

`/cordon-review` is model-invocable (Claude should *drive toward* it).
`/cordon-accept` and `/cordon-discard` carry
`disable-model-invocation: true`: the irreversible acts — landing work,
destroying work — require a human keystroke. The asymmetry is the gate.
Accept lands `HEAD` onto a fresh `cordon-accepted/*` branch (branches are
shared across worktrees, so it's instantly visible in the main checkout) and
*stops there*: merging or pushing is the human's deliberate final act.

## Failure-mode table

| Failure | Caught by |
|---|---|
| Claude forgets the rules (drift) | hooks + deny rules (hard layer) |
| Hook script deleted/edited mid-session | deny rules block `.claude` edits; sandbox denies settings writes; managed tier if deployed |
| Compound-command smuggling (`a && git push`) | platform splits compounds for deny rules; hook regexes scan full string |
| Path traversal / symlinked parent dirs | boundary hook canonicalization + tests |
| Creative shell evasion of string matching | OS sandbox (the layer that doesn't parse, it contains) |
| Sandbox unavailable on the OS | statusline shows it; `failIfUnavailable` in managed tier makes it fatal |
| Determined human editing project config | managed settings only — and that's explicitly out of scope otherwise |
| `--dangerously-skip-permissions` launch | **nothing at project scope** — verified live that bypass mode skips the boundary hook. Only managed `disableBypassPermissionsMode: "disable"` closes it. Cordon assumes a cooperative operator who doesn't launch with the "no guardrails" flag. |

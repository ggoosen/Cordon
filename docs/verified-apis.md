# Verified API surface

Every claim below was checked against **Claude Code CLI 2.1.168** and the live
docs at `code.claude.com/docs` on **2026-06-07**. Re-verify before relying on
this after a major CLI upgrade. Where reality differed from the original design
spec, the difference and the design consequence are noted.

## Worktrees

- `claude --worktree [name]` / `-w` exists. Creates the worktree at
  **`.claude/worktrees/<name>/`** under the repository root, on a new branch
  named **`worktree-<name>`**, branched from `origin/HEAD` (falls back to local
  `HEAD`; `worktree.baseRef: "head"` forces local HEAD).
- Requires workspace trust: run `claude` once in the directory first, or
  `--worktree` exits with an error.
- **`EnterWorktree` tool exists** — Claude can create/enter a worktree
  *mid-session*. Design consequence: the governance layer instructs Claude to
  enter a worktree itself instead of only telling the user to relaunch. This is
  better than the spec hoped for.
- Cleanup on exit: clean worktrees (no changes, no new commits) are removed
  automatically; dirty ones prompt keep/remove. `-p` runs are never cleaned up.
- `.worktreeinclude` (gitignore syntax) copies gitignored files (e.g. `.env`)
  into new worktrees.

## Hooks

- **PreToolUse** stdin JSON: `session_id`, `transcript_path`, `cwd`,
  `permission_mode`, `hook_event_name`, `tool_name`, `tool_input`.
- Deny mechanisms (both verified):
  - `exit 2` with reason on stderr → blocks the call, stderr shown to Claude.
  - `exit 0` + stdout JSON:
    `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`
    (`permissionDecision` ∈ `allow` | `deny` | `ask` | `defer`).
    JSON is only processed on exit 0.
  - Cordon uses the JSON form; internal errors fail **closed** via `exit 2`.
- A blocking hook takes precedence over `allow` permission rules; `deny`/`ask`
  permission rules are evaluated regardless of hook output. Defense in depth
  works in the right direction.
- **SessionStart `exit 2` does NOT halt startup** — it only shows stderr.
  There is no blocking mechanism for SessionStart. Design consequence (the
  spec's anticipated fallback): the startup gate *informs* (via
  `additionalContext`), and **strict enforcement lives in the PreToolUse
  boundary hook**, which denies file mutations outside a worktree when
  `CORDON_POLICY=strict`.
- SessionStart matchers: `startup`, `resume`, `clear`, `compact`.
- SessionStart stdout JSON supports `additionalContext` (and plain stdout is
  also injected as context).
- PostToolUse stdin adds `tool_use_result`; exit 2 there is non-blocking.
- `$CLAUDE_PROJECT_DIR` is exported to hook processes and usable in hook
  `command` strings. Plugins get `${CLAUDE_PLUGIN_ROOT}`.
- Hook exit codes other than 0/2 are **non-blocking errors** — i.e. a crashing
  hook fails *open*. Cordon's hooks trap errors and convert them to `exit 2`
  (fail closed).

## Permission rules

- Canonical Bash glob form is space-separated: `Bash(git push *)`.
  `:*` is equivalent **only as a trailing suffix**. A trailing ` *` enforces a
  word boundary and does **not** match the bare command — `Bash(git push *)`
  does not match `git push`, so Cordon ships both forms for each deny.
- Compound commands (`&&`, `||`, `;`, `|`, newlines) are split and each
  subcommand must match independently — deny rules cannot be smuggled past in
  a compound. Process wrappers (`timeout`, `nice`, …) are stripped before
  matching; env-runner wrappers (`npx`, `docker exec`) are not.
- `Read`/`Edit` rules are gitignore-style: `//abs`, `~/home`, `/project-root`,
  bare = cwd-relative (bare filenames match at any depth: `Read(.env)` ≡
  `Read(**/.env)`). `Edit` rules cover all built-in file-editing tools
  (Write, NotebookEdit included).
- `Read`/`Edit` deny rules also cover recognized file commands in Bash
  (`cat`, `sed`, …) but **not** arbitrary subprocesses — that's the sandbox's
  job.
- Deny → ask → allow evaluation order; deny rules merge across scopes and
  cannot be loosened by a lower scope.
- `permissions.defaultMode` values: `default`, `acceptEdits`, `plan`, `auto`,
  `dontAsk`, `bypassPermissions`.

## Sandbox

- Settings shape (verified): `sandbox.enabled`,
  `sandbox.filesystem.{allowWrite,denyWrite,allowRead,denyRead}`,
  `sandbox.network.{allowedDomains,deniedDomains,httpProxyPort,socksProxyPort}`,
  `sandbox.{excludedCommands,allowUnsandboxedCommands,failIfUnavailable,autoAllowBashIfSandboxed}`.
- OS support: macOS via **Seatbelt (built-in, nothing to install)**; Linux/WSL2
  via bubblewrap + socat. Native Windows unsupported. If unavailable, default
  behavior is **warn and run unsandboxed** — set `failIfUnavailable: true`
  (managed settings) to make it a hard gate.
- Defaults: writes confined to the working directory; reads mostly open
  (`~/.ssh`, `~/.aws` are readable by default → Cordon adds `denyRead`).
- The sandbox automatically denies writes to every `settings.json` scope, and
  in **linked git worktrees** allows writes to the shared `.git` dir *except*
  `hooks/` and `config` — so `git commit` works inside the sandbox while hook
  injection stays blocked.
- `autoAllowBashIfSandboxed` defaults to true: sandboxed Bash runs without
  prompts; explicit deny rules still apply. This is what makes Cordon sessions
  feel autonomous *inside* the boundary.
- Sandbox `filesystem` paths use standard conventions (`/` = absolute), unlike
  permission rules.
- Honest limit: the network proxy allowlists by client-supplied hostname
  without TLS inspection (domain fronting is possible); not an adversary
  boundary.

## Skills

- Project skills: `.claude/skills/<dir>/SKILL.md` → `/<dir>`. Plugin skills:
  `<plugin>/skills/<dir>/SKILL.md` → `/<plugin-name>:<dir>` (directory name,
  not frontmatter `name`, sets the command).
- Frontmatter keys (verified): `name` (display only), `description`,
  `disable-model-invocation` (true → only the human can invoke),
  `user-invocable` (default true), `allowed-tools` (space/comma separated),
  `argument-hint`, `context: fork`, `agent`, `model`, `hooks`, …
- `allowed-tools` pre-approves tools while the skill is active; it does **not**
  bypass deny rules or PreToolUse hooks.
- Dynamic context injection `` !`cmd` `` is verified: runs before Claude sees
  the content; `!` must start a line or follow whitespace.
- `disableSkillShellExecution: true` (managed) turns injection off.

## Managed settings

- Locations: macOS `/Library/Application Support/ClaudeCode/managed-settings.json`,
  Linux/WSL `/etc/claude-code/managed-settings.json`,
  Windows `C:\Program Files\ClaudeCode\managed-settings.json`
  (+ `managed-settings.d/` drop-ins). Highest precedence; cannot be overridden,
  including by CLI flags.
- Useful lockdown keys: `permissions.disableBypassPermissionsMode: "disable"`,
  `sandbox.failIfUnavailable`, `sandbox.allowUnsandboxedCommands: false`,
  `allowManagedPermissionRulesOnly`, `sandbox.network.allowManagedDomainsOnly`.
- Caution: `allowManagedHooksOnly: true` would block Cordon's **project**
  hooks — if you use it, ship Cordon's hooks via managed settings or a
  force-enabled plugin instead.

## CLAUDE.md

- Auto-discovered at the project root (and `.claude/CLAUDE.md`); loaded every
  session. `--bare` disables auto-discovery.
- Worktree sessions get the worktree checkout's own `CLAUDE.md` — since Cordon
  is committed to the repo, the governance brain travels into every worktree
  automatically.
- Instructions in CLAUDE.md shape what Claude *tries*; they are not enforced
  by Claude Code (the docs say this explicitly). Hard rules must live in
  permissions/hooks/sandbox.

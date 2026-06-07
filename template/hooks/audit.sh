#!/usr/bin/env bash
# Cordon audit trail (G5): one JSON line per observed tool use.
#
# Writes to <main checkout>/.claude/cordon-audit.jsonl — the MAIN checkout
# even when running inside a worktree, so the trail survives a discarded
# worktree. Gitignored by install.sh. Mirrors Sandkeep's audit format so the
# two harnesses produce comparable trails.
#
# Logging must never break the session: this hook always exits 0.
set -uo pipefail

. "$(cd "$(dirname "$0")" && pwd -P)/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)" || exit 0
[ -n "$cwd" ] || cwd="$PWD"

log_dir="$(cordon_main_root "$cwd")/.claude"
[ -d "$log_dir" ] || mkdir -p "$log_dir" 2>/dev/null || exit 0

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Truncate long strings (file contents etc.) so the log stays readable and
# small; the diff is the source of truth for content, the log is for "what
# happened when".
jq -c --arg ts "$ts" '
  def trunc: if type == "string" and length > 400 then .[0:400] + "…[truncated]" else . end;
  {ts: $ts,
   event: .hook_event_name,
   tool: .tool_name,
   session: .session_id,
   cwd: .cwd,
   input: (.tool_input | if type == "object" then with_entries(.value |= trunc) else trunc end)}
' <<<"$input" >>"$log_dir/cordon-audit.jsonl" 2>/dev/null || true

exit 0

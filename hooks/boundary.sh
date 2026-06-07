#!/usr/bin/env bash
# Cordon PreToolUse boundary guard — the active-enforcement lever.
#
# Reads the pending tool call on stdin and DENIES any action that would
# leave the worktree, touch .git/.claude, reach the raw network, or use one
# of the blocked escape hatches. Everything else falls through to the normal
# permission flow (exit 0, no output).
#
# This hook backs up the static permissions.deny rules and the OS sandbox:
# three layers, each catching what the others miss. It fails CLOSED — any
# internal error blocks the call rather than allowing it.
set -euo pipefail
trap 'cordon_fail_closed "boundary.sh trap"' ERR

# shellcheck source=lib.sh
. "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

cordon_require jq

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -n "$cwd" ] || cwd="$PWD"

deny() { # $1 = reason
  # Best-effort audit of the denial (G5) — must never break the deny itself.
  {
    log_dir="$(cordon_main_root "$cwd")/.claude"
    [ -d "$log_dir" ] && jq -nc \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg t "$tool" --arg r "$1" \
      '{ts:$ts, event:"PreToolUse-denied", tool:$t, reason:$r}' \
      >>"$log_dir/cordon-audit.jsonl"
  } 2>/dev/null || true
  jq -n --arg r "Cordon: $1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",
      permissionDecision:"deny", permissionDecisionReason:$r}}'
  exit 0
}

policy="$(cordon_policy)"
# Canonicalize the boundary root so prefix checks survive symlinked paths
# (macOS /var → /private/var, symlinked home dirs, …).
root="$(cordon_resolve "$(cordon_boundary_root "$cwd")")"

case "$tool" in

  Edit | Write | NotebookEdit)
    path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' <<<"$input")"
    [ -n "$path" ] || exit 0

    if [ "$policy" = "strict" ] && ! cordon_in_worktree "$cwd"; then
      deny "this session is not isolated, and policy is strict. Enter a worktree first (EnterWorktree tool) or relaunch with 'claude --worktree'. File edits outside an isolated worktree are blocked."
    fi

    abs="$(cordon_resolve "$(cordon_abspath "$path" "$cwd")")"

    rel=""
    case "$abs" in
      "$root") rel="." ;;
      "$root"/*) rel="${abs#"$root"/}" ;;
      *) deny "edits must stay inside the workspace ($root) — refusing to touch $abs" ;;
    esac

    # Protected paths, checked RELATIVE to the boundary root. (Checking the
    # absolute path would false-positive on every file in a worktree, since
    # worktrees live under <repo>/.claude/worktrees/.)
    case "/$rel/" in
      */.git/* | */.git) deny "writing into .git is not allowed" ;;
    esac
    case "/$rel/" in
      */.claude/* | */.claude) deny ".claude (Cordon settings, hooks, skills) is protected — policy changes are a deliberate human act, not part of a task" ;;
    esac
    ;;

  Bash)
    cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
    [ -n "$cmd" ] || exit 0

    # Escape hatches the static deny rules might miss (quoting tricks,
    # wrappers, compound forms). Word-boundary regexes, not substrings, so
    # "curlify" passes while "curl" is caught. Regexes live in variables —
    # bash cannot parse `;`/`|` literally inside an inline =~ expression.
    # Best-effort by design: the permissions.deny rules and the sandbox are
    # the other two layers.
    re_push='(^|[^[:alnum:]_.-])git[[:space:]]+([^|;&]*[[:space:]])?push([[:space:]]|$)'
    re_reset='(^|[^[:alnum:]_.-])git[[:space:]]+reset[[:space:]]+--(hard|merge)'
    re_mainbr='(^|[^[:alnum:]_.-])git[[:space:]]+(checkout|switch)[[:space:]]+(main|master)([[:space:]]|$)'
    re_net='(^|[;&|[:space:]])(curl|wget|nc|ncat|telnet)([[:space:]]|$)'
    re_sudo='(^|[;&|[:space:]])sudo([[:space:]]|$)'
    re_rmrf='(^|[;&|[:space:]])rm[[:space:]]+-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])'
    re_redir='(>|>>|[[:space:]]tee[[:space:]])[^|;&]*\.(git|claude)/'

    if [[ "$cmd" =~ $re_push ]]; then
      deny "git push is blocked; finish with /cordon-review, then /cordon-accept lands the work on a branch the human pushes"
    fi
    if [[ "$cmd" =~ $re_reset ]]; then
      deny "hard reset is blocked inside a Cordon session — use /cordon-discard to throw the worktree away instead"
    fi
    if [[ "$cmd" =~ $re_mainbr ]]; then
      deny "switching to main/master is blocked — work stays on the worktree branch until /cordon-accept"
    fi
    if [[ "$cmd" =~ $re_net ]]; then
      deny "raw network egress is blocked; use the session's own tools (WebFetch/MCP) instead"
    fi
    if [[ "$cmd" == */dev/tcp/* || "$cmd" == */dev/udp/* ]]; then
      deny "network egress via /dev/tcp is blocked"
    fi
    if [[ "$cmd" =~ $re_sudo ]]; then
      deny "sudo is not available in a Cordon session"
    fi
    if [[ "$cmd" =~ $re_rmrf ]]; then
      deny "recursive force-delete is blocked — use /cordon-discard to throw away the worktree, or delete files individually"
    fi
    if [[ "$cmd" =~ $re_redir ]]; then
      deny "shell redirection into .git/.claude is not allowed"
    fi
    ;;

esac

exit 0 # allow — normal permission flow still applies

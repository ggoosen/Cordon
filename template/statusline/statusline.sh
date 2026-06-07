#!/usr/bin/env bash
# Cordon statusline: surface the REAL isolation state at all times.
# Shows: worktree name (or a loud main-checkout warning) · sandbox config ·
# change count. Never let "off" look like "on".
set -uo pipefail

. "$(cd "$(dirname "$0")/../hooks" && pwd -P)/lib.sh" 2>/dev/null || true

input="$(cat 2>/dev/null || true)"
cwd=""
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  cwd="$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

# Isolation state
if cordon_in_worktree "$cwd" 2>/dev/null; then
  wt="wt:$(basename "$cwd")"
else
  wt="⚠ MAIN CHECKOUT"
fi

# Sandbox state: report the CONFIGURED state honestly. We cannot introspect
# the live sandbox from here, so say "cfg" — and say OFF loudly when off.
sb="sandbox:OFF"
settings="$cwd/.claude/settings.json"
[ -f "$settings" ] || settings="${CLAUDE_PROJECT_DIR:-$cwd}/.claude/settings.json"
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  if [ "$(jq -r '.sandbox.enabled // false' "$settings" 2>/dev/null)" = "true" ]; then
    sb="sandbox:cfg-on"
  fi
fi

# Change count in this checkout
n="$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
[ -n "$n" ] || n=0

policy="$(CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$cwd}" cordon_policy 2>/dev/null || echo '?')"

printf 'cordon[%s] · %s · %s · Δ%s' "$policy" "$wt" "$sb" "$n"

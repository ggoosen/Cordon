#!/usr/bin/env bash
# Cordon SessionStart gate.
#
# Verified at build time (CLI 2.1.168): SessionStart hooks CANNOT block
# startup — exit 2 only prints stderr. So this hook does what a SessionStart
# hook can actually do: inject authoritative context that tells Claude the
# session's isolation state and what to do about it. The HARD enforcement
# for an un-isolated strict session lives in boundary.sh, which denies file
# mutations outside a worktree. This gate is the narration layer's anchor.
set -euo pipefail
trap 'echo "Cordon: enforce-isolation hook error" >&2; exit 0' ERR

# shellcheck source=lib.sh
. "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

cordon_require jq

input="$(cat)"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -n "$cwd" ] || cwd="$PWD"

policy="$(cordon_policy)"

emit() { # $1 = additionalContext
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
  exit 0
}

if cordon_in_worktree "$cwd"; then
  branch="$(git -C "$cwd" branch --show-current 2>/dev/null || echo '?')"
  name="$(basename "$cwd")"
  emit "[Cordon] Isolated session ACTIVE. Worktree: ${name} (branch: ${branch}), policy: ${policy}. House rules are in CLAUDE.md. Open by telling the user, in one line, that work is isolated here and will be gated through /cordon-review before it can land."
fi

# Not isolated. Tell the user on stderr is not possible without forfeiting
# the JSON channel, so the statusline shows the warning state and Claude is
# instructed to surface it immediately.
if [ "$policy" = "strict" ]; then
  emit "[Cordon] WARNING: this session is NOT isolated (main checkout, policy: strict). File edits and risky commands WILL BE DENIED by the boundary hook. Before doing any work: tell the user this session is not isolated, then either (a) enter an isolated worktree yourself with the EnterWorktree tool, or (b) ask them to relaunch with 'claude --worktree'. Do not attempt edits until isolated."
else
  emit "[Cordon] NOTICE: this session is NOT isolated (main checkout, policy: guided). Recommend isolation before substantive work: offer to enter a worktree (EnterWorktree tool) or suggest relaunching with 'claude --worktree'. Mention it once, briefly, then proceed as the user prefers."
fi

#!/usr/bin/env bash
# cordon-doctor — verify the Cordon infrastructure is actually in place and live.
#
# Run from anywhere inside a Cordon-governed repo:
#   .claude/cordon-doctor.sh
#
# Three kinds of checks:
#   - files & wiring: everything installed, executable, and registered
#   - LIVE FIRE: real payloads through the hooks — proof the guard runs
#   - environment: jq, sandbox dependencies, rails committed to git
#
# Exits non-zero if anything that matters is broken. Warnings don't fail.
set -uo pipefail

PASS=0 FAIL=0 WARN=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        fix: %s\n' "$1" "$2"; }
warn() { WARN=$((WARN + 1)); printf '  warn  %s\n' "$1"; }
info() { printf '  ·     %s\n' "$1"; }

echo "cordon-doctor"
echo

# ── environment ────────────────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
  ok "jq present ($(jq --version 2>/dev/null))"
else
  bad "jq missing — the hooks fail closed without it (every guarded call denied)" \
    "brew install jq  /  apt install jq"
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  bad "not inside a git repository" "cd into your Cordon-governed repo"
  echo
  echo "doctor: $PASS ok, $FAIL failed, $WARN warnings"
  exit 1
}
git rev-parse HEAD >/dev/null 2>&1 && ok "git repo with commits ($ROOT)" ||
  bad "repo has no commits — worktrees need at least one" "git commit --allow-empty -m init"

case "$(uname -s)" in
  Darwin) ok "macOS: sandbox uses built-in Seatbelt (nothing to install)" ;;
  Linux)
    if command -v bwrap >/dev/null 2>&1 && command -v socat >/dev/null 2>&1; then
      ok "Linux: bubblewrap + socat present (sandbox can run)"
    else
      warn "Linux: bubblewrap and/or socat missing — sandbox will WARN AND RUN UNSANDBOXED. Install: apt install bubblewrap socat"
    fi
    ;;
  *) warn "unsupported OS for the sandbox ($(uname -s)) — boundary hook + deny rules are your only layers" ;;
esac

# ── files & wiring ─────────────────────────────────────────────────────────
S="$ROOT/.claude/settings.json"
if [ -f "$S" ] && jq -e . "$S" >/dev/null 2>&1; then
  ok ".claude/settings.json present and parses"
  [ "$(jq -r '.sandbox.enabled // false' "$S")" = "true" ] &&
    ok "sandbox enabled in settings (run /sandbox in a session for LIVE state)" ||
    bad "sandbox not enabled in settings" "restore \"sandbox\": {\"enabled\": true} (re-run install.sh)"
  jq -e '.hooks.PreToolUse[]?.hooks[]?.command | select(contains("boundary.sh"))' "$S" >/dev/null 2>&1 &&
    ok "boundary hook wired (PreToolUse)" ||
    bad "boundary hook NOT wired in settings" "re-run install.sh"
  jq -e '.hooks.SessionStart[]?.hooks[]?.command | select(contains("enforce-isolation.sh"))' "$S" >/dev/null 2>&1 &&
    ok "isolation gate wired (SessionStart)" ||
    bad "isolation gate NOT wired in settings" "re-run install.sh"
  jq -e '.hooks.PostToolUse[]?.hooks[]?.command | select(contains("audit.sh"))' "$S" >/dev/null 2>&1 &&
    ok "audit hook wired (PostToolUse)" ||
    bad "audit hook NOT wired in settings" "re-run install.sh"
  jq -e '.statusLine.command | select(contains("statusline.sh"))' "$S" >/dev/null 2>&1 &&
    ok "statusline wired" || warn "statusline not wired — you lose the at-a-glance isolation indicator"
  for rule in 'Bash(git push *)' 'Bash(curl *)' 'Edit(.claude/**)'; do
    jq -e --arg r "$rule" '.permissions.deny | index($r)' "$S" >/dev/null 2>&1 &&
      ok "deny rule: $rule" ||
      bad "deny rule missing: $rule" "re-run install.sh (or merge from template/settings.json)"
  done
else
  bad ".claude/settings.json missing or invalid" "re-run install.sh"
fi

for h in boundary.sh enforce-isolation.sh audit.sh lib.sh; do
  if [ -x "$ROOT/.claude/hooks/$h" ]; then
    ok "hook present + executable: $h"
  else
    bad "hook missing or not executable: .claude/hooks/$h" "re-run install.sh (or chmod +x .claude/hooks/$h)"
  fi
done
[ -x "$ROOT/.claude/statusline/statusline.sh" ] && ok "statusline script present + executable" ||
  warn "statusline script missing"

missing_skills=""
for sk in cordon-review cordon-accept cordon-discard cordon-status; do
  [ -f "$ROOT/.claude/skills/$sk/SKILL.md" ] || missing_skills="$missing_skills $sk"
done
[ -z "$missing_skills" ] && ok "all four gate skills present (/cordon-review /cordon-accept /cordon-discard /cordon-status)" ||
  bad "missing skills:$missing_skills" "re-run install.sh"

if [ -f "$ROOT/.claude/cordon.config" ]; then
  pol="$(sed -n 's/^CORDON_POLICY=//p' "$ROOT/.claude/cordon.config" | head -1 | tr -d '[:space:]')"
  case "$pol" in
    strict | guided) ok "policy: $pol (.claude/cordon.config)" ;;
    *) bad "invalid CORDON_POLICY '$pol'" "set CORDON_POLICY=strict or guided in .claude/cordon.config" ;;
  esac
else
  warn "no .claude/cordon.config — hooks default to strict"
fi

if [ -f "$ROOT/CLAUDE.md" ] && grep -q 'BEGIN CORDON GOVERNANCE' "$ROOT/CLAUDE.md"; then
  posture="$(sed -n 's/.*BEGIN CORDON GOVERNANCE (posture: \([a-z]*\)).*/\1/p' "$ROOT/CLAUDE.md" | head -1)"
  ok "CLAUDE.md governance block present (posture: ${posture:-?})"
else
  bad "CLAUDE.md governance block missing — Claude won't know the house rules" "re-run install.sh"
fi

for line in ".claude/worktrees/" ".claude/cordon-audit.jsonl"; do
  grep -qxF "$line" "$ROOT/.gitignore" 2>/dev/null && ok ".gitignore: $line" ||
    warn ".gitignore missing '$line' — worktree contents / audit log will show as untracked"
done

# Rails must be COMMITTED — a worktree is a fresh checkout of the repo, so
# uncommitted .claude/CLAUDE.md files do NOT travel into worktree sessions.
uncommitted=""
for f in CLAUDE.md .claude/settings.json .claude/hooks/boundary.sh; do
  git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1 || uncommitted="$uncommitted $f"
done
if [ -z "$uncommitted" ]; then
  ok "rails are committed to git (they travel into every worktree)"
else
  bad "NOT committed:$uncommitted — worktree sessions will run WITHOUT Cordon" \
    "git add CLAUDE.md .claude .gitignore && git commit -m 'add cordon'"
fi

# ── live fire ──────────────────────────────────────────────────────────────
B="$ROOT/.claude/hooks/boundary.sh"
if [ -x "$B" ] && command -v jq >/dev/null 2>&1; then
  out="$(jq -n --arg c "$ROOT" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$c,tool_input:{command:"git push origin main"}}' | "$B" 2>/dev/null)"
  jq -e '.hookSpecificOutput.permissionDecision=="deny"' <<<"$out" >/dev/null 2>&1 &&
    ok "LIVE: boundary denies 'git push'" ||
    bad "LIVE: boundary did NOT deny 'git push'" "check .claude/hooks/boundary.sh (run it by hand with a payload)"

  out="$(jq -n --arg c "$ROOT" '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$c,tool_input:{file_path:"/etc/passwd"}}' | "$B" 2>/dev/null)"
  jq -e '.hookSpecificOutput.permissionDecision=="deny"' <<<"$out" >/dev/null 2>&1 &&
    ok "LIVE: boundary denies write outside the workspace" ||
    bad "LIVE: boundary did NOT deny an outside write" "check .claude/hooks/boundary.sh"

  out="$(jq -n --arg c "$ROOT" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$c,tool_input:{command:"git status"}}' | "$B" 2>/dev/null)"
  rc=$?
  if [ $rc -eq 0 ] && ! jq -e '.hookSpecificOutput.permissionDecision=="deny"' <<<"${out:-null}" >/dev/null 2>&1; then
    ok "LIVE: boundary allows benign commands (git status)"
  else
    bad "LIVE: boundary wrongly blocks benign commands" "check .claude/hooks/boundary.sh"
  fi
else
  bad "cannot live-fire the boundary hook (missing script or jq)" "fix the failures above first"
fi

ISO="$ROOT/.claude/hooks/enforce-isolation.sh"
if [ -x "$ISO" ] && command -v jq >/dev/null 2>&1; then
  out="$(jq -n --arg c "$ROOT" '{hook_event_name:"SessionStart",source:"startup",cwd:$c}' | "$ISO" 2>/dev/null)"
  jq -e '.hookSpecificOutput.additionalContext | contains("Cordon")' <<<"$out" >/dev/null 2>&1 &&
    ok "LIVE: SessionStart gate injects isolation context" ||
    bad "LIVE: SessionStart gate produced no context" "check .claude/hooks/enforce-isolation.sh"
fi

# ── current state (informational) ──────────────────────────────────────────
echo
gd="$(git rev-parse --git-dir 2>/dev/null)"
case "$gd" in
  */worktrees/*) info "you are currently INSIDE an isolated worktree ($(basename "$ROOT"))" ;;
  *) info "you are in the MAIN checkout — start isolated sessions with: claude --worktree" ;;
esac
[ -f "$ROOT/.claude/cordon-audit.jsonl" ] &&
  info "audit trail: $(wc -l <"$ROOT/.claude/cordon-audit.jsonl" | tr -d ' ') entries (.claude/cordon-audit.jsonl)" ||
  info "audit trail: none yet (created on first tool use)"
info "live sandbox state can only be seen in-session: run /sandbox"

echo
echo "doctor: $PASS ok, $FAIL failed, $WARN warnings"
if [ "$FAIL" -eq 0 ]; then
  echo "Cordon is in place. Start an isolated session with: claude --worktree"
else
  echo "Cordon is NOT fully in place — fix the FAIL lines above."
fi
[ "$FAIL" -eq 0 ]

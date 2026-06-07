#!/usr/bin/env bash
# Tests for the startup gate, audit hook, settings sanity, the installer,
# and template↔plugin drift.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL   %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else fail "$1"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cordon-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
MAIN="$TMP/main"
mkdir -p "$MAIN"
git -C "$TMP" init -q -b main main
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$MAIN/.claude/worktrees"
git -C "$MAIN" worktree add -q -b worktree-wt1 "$MAIN/.claude/worktrees/wt1" main
WT="$MAIN/.claude/worktrees/wt1"

ISO="$ROOT/template/hooks/enforce-isolation.sh"
AUD="$ROOT/template/hooks/audit.sh"

session_payload() { jq -n --arg c "$1" '{hook_event_name:"SessionStart", source:"startup", cwd:$c}'; }

echo "— SessionStart isolation gate —"
out="$(session_payload "$MAIN" | CORDON_POLICY=strict bash "$ISO")"
rc=$?
[ $rc -eq 0 ] && ok "strict outside worktree → exits 0 (cannot block; informs instead)" || fail "strict outside worktree → exits 0 (got rc=$rc)"
jq -e '.hookSpecificOutput.additionalContext | contains("NOT isolated")' <<<"$out" >/dev/null 2>&1 && ok "strict context warns NOT isolated" || fail "strict context warns NOT isolated"
jq -e '.hookSpecificOutput.additionalContext | contains("WILL BE DENIED")' <<<"$out" >/dev/null 2>&1 && ok "strict context says edits will be denied" || fail "strict context says edits will be denied"
jq -e '.hookSpecificOutput.additionalContext | contains("EnterWorktree")' <<<"$out" >/dev/null 2>&1 && ok "strict context offers EnterWorktree" || fail "strict context offers EnterWorktree"
jq -e '.hookSpecificOutput.additionalContext | contains("claude --worktree")' <<<"$out" >/dev/null 2>&1 && ok "strict context names the relaunch command" || fail "strict context names the relaunch command"

out="$(session_payload "$MAIN" | CORDON_POLICY=guided bash "$ISO")"
jq -e '.hookSpecificOutput.additionalContext | contains("NOTICE")' <<<"$out" >/dev/null 2>&1 && ok "guided outside worktree → soft notice" || fail "guided outside worktree → soft notice"

out="$(session_payload "$WT" | CORDON_POLICY=strict bash "$ISO")"
jq -e '.hookSpecificOutput.additionalContext | contains("Isolated session ACTIVE")' <<<"$out" >/dev/null 2>&1 && ok "inside worktree → active confirmation" || fail "inside worktree → active confirmation"
jq -e '.hookSpecificOutput.additionalContext | contains("wt1")' <<<"$out" >/dev/null 2>&1 && ok "inside worktree → names the worktree" || fail "inside worktree → names the worktree"

echo "— audit hook —"
jq -n --arg c "$WT" '{hook_event_name:"PostToolUse", tool_name:"Write", session_id:"s1", cwd:$c, tool_input:{file_path:"x", content:("A"*1000)}}' \
  | bash "$AUD"
LOG="$MAIN/.claude/cordon-audit.jsonl"
check "audit log written to MAIN checkout (survives worktree discard)" "[ -f '$LOG' ]"
check "audit line is valid JSON with tool name" "jq -e 'select(.tool==\"Write\" and .session==\"s1\")' '$LOG'"
check "audit truncates long content" "grep -q 'truncated' '$LOG'"

echo "— settings sanity —"
S="$ROOT/template/settings.json"
check "settings.json parses" "jq -e . '$S'"
for rule in 'Bash(git push *)' 'Bash(git push)' 'Bash(git reset --hard *)' 'Bash(sudo *)' 'Bash(curl *)' 'Edit(.git/**)' 'Edit(.claude/**)' 'Read(.env)' 'Read(~/.ssh/**)'; do
  check "deny rule present: $rule" "jq -e --arg r '$rule' '.permissions.deny | index(\$r)' '$S'"
done
check "sandbox enabled" "jq -e '.sandbox.enabled == true' '$S'"
check "boundary hook wired on PreToolUse" "jq -e '.hooks.PreToolUse[0].hooks[0].command | contains(\"boundary.sh\")' '$S'"
check "isolation hook wired on SessionStart startup+resume+clear" "[ \"\$(jq -r '.hooks.SessionStart | length' '$S')\" = '3' ]"
check "audit hook wired on PostToolUse" "jq -e '.hooks.PostToolUse[0].hooks[0].command | contains(\"audit.sh\")' '$S'"
check "statusline wired" "jq -e '.statusLine.command | contains(\"statusline.sh\")' '$S'"
check "managed-settings example parses" "jq -e . '$ROOT/managed-settings.example.json'"
check "plugin manifest parses" "jq -e '.name == \"cordon\"' '$ROOT/.claude-plugin/plugin.json'"
check "plugin hooks.json parses" "jq -e .hooks '$ROOT/hooks/hooks.json'"

echo "— executables —"
for f in "$ROOT"/template/hooks/*.sh "$ROOT/template/statusline/statusline.sh" "$ROOT/install.sh" "$ROOT/scripts/sync-plugin.sh"; do
  check "executable: ${f#"$ROOT"/}" "[ -x '$f' ]"
done
for f in "$ROOT"/template/hooks/*.sh "$ROOT/template/statusline/statusline.sh" "$ROOT/install.sh"; do
  check "bash -n: ${f#"$ROOT"/}" "bash -n '$f'"
done

echo "— statusline —"
out="$(jq -n --arg c "$WT" '{workspace:{current_dir:$c}}' | CLAUDE_PROJECT_DIR="$WT" bash "$ROOT/template/statusline/statusline.sh")"
case "$out" in *wt:wt1*) ok "statusline shows worktree name" ;; *) fail "statusline shows worktree name (got: $out)" ;; esac
out="$(jq -n --arg c "$MAIN" '{workspace:{current_dir:$c}}' | CLAUDE_PROJECT_DIR="$MAIN" bash "$ROOT/template/statusline/statusline.sh")"
case "$out" in *"MAIN CHECKOUT"*) ok "statusline warns on main checkout" ;; *) fail "statusline warns on main checkout (got: $out)" ;; esac

echo "— installer (into a fresh fixture repo) —"
TGT="$TMP/target"
mkdir -p "$TGT"
git -C "$TMP" init -q -b main target
git -C "$TGT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo "# Existing project notes" >"$TGT/CLAUDE.md"
bash "$ROOT/install.sh" "$TGT" --posture enforce --policy strict >/dev/null
check "installer: settings.json placed" "[ -f '$TGT/.claude/settings.json' ]"
check "installer: hooks placed + executable" "[ -x '$TGT/.claude/hooks/boundary.sh' ]"
check "installer: all five skills placed" "[ -f '$TGT/.claude/skills/cordon-review/SKILL.md' ] && [ -f '$TGT/.claude/skills/cordon-accept/SKILL.md' ] && [ -f '$TGT/.claude/skills/cordon-discard/SKILL.md' ] && [ -f '$TGT/.claude/skills/cordon-status/SKILL.md' ] && [ -f '$TGT/.claude/skills/cordon-update/SKILL.md' ]"
check "installer: version stamped in cordon.config" "grep -q '^CORDON_VERSION=' '$TGT/.claude/cordon.config'"
check "installer: statusline placed" "[ -x '$TGT/.claude/statusline/statusline.sh' ]"
check "installer: cordon.config stamped strict" "grep -qx 'CORDON_POLICY=strict' '$TGT/.claude/cordon.config'"
check "installer: CLAUDE.md keeps existing content" "grep -q 'Existing project notes' '$TGT/CLAUDE.md'"
check "installer: CLAUDE.md has enforce posture" "grep -q 'posture: enforce' '$TGT/CLAUDE.md'"
check "installer: .gitignore wired" "grep -qx '.claude/worktrees/' '$TGT/.gitignore' && grep -qx '.claude/cordon-audit.jsonl' '$TGT/.gitignore'"
# idempotency + posture switch
bash "$ROOT/install.sh" "$TGT" --posture guide --policy guided >/dev/null
check "installer: re-run switches posture without duplicating" "[ \"\$(grep -c 'BEGIN CORDON GOVERNANCE' '$TGT/CLAUDE.md')\" = '1' ] && grep -q 'posture: guide' '$TGT/CLAUDE.md'"
check "installer: re-run switches policy" "grep -qx 'CORDON_POLICY=guided' '$TGT/.claude/cordon.config'"
check "installer: .gitignore not duplicated" "[ \"\$(grep -cx '.claude/worktrees/' '$TGT/.gitignore')\" = '1' ]"
# bare re-run (update) must PRESERVE previously chosen posture/policy
bash "$ROOT/install.sh" "$TGT" >/dev/null
check "installer: bare re-run preserves posture (guide)" "grep -q 'posture: guide' '$TGT/CLAUDE.md'"
check "installer: bare re-run preserves policy (guided)" "grep -qx 'CORDON_POLICY=guided' '$TGT/.claude/cordon.config'"

echo "— skill injections must be statically analyzable —"
# The permission layer rejects injected !`…` commands containing shell syntax
# ($(), ||, &&, ;, |, redirects). Regression for a real-world failure.
badlines="$(grep -hoE '!`[^`]*`' "$ROOT"/template/skills/*/SKILL.md | grep -E '\$\(|\|\||&&|;|\||>' || true)"
if [ -z "$badlines" ]; then
  ok "no compound shell in skill context injections"
else
  fail "skill injections contain unanalyzable shell: $badlines"
fi

echo "— cordon-doctor —"
check "installer: doctor placed + executable" "[ -x '$TGT/.claude/cordon-doctor.sh' ]"
git -C "$TGT" add -A >/dev/null 2>&1 && git -C "$TGT" -c user.email=t@t -c user.name=t commit -qm "rails" >/dev/null 2>&1
( cd "$TGT" && bash .claude/cordon-doctor.sh >/dev/null 2>&1 )
check "doctor passes on a healthy install" "( cd '$TGT' && bash .claude/cordon-doctor.sh >/dev/null 2>&1 )"
chmod -x "$TGT/.claude/hooks/boundary.sh"
if ( cd "$TGT" && bash .claude/cordon-doctor.sh >/dev/null 2>&1 ); then
  fail "doctor should fail when boundary.sh is not executable"
else
  ok "doctor fails when boundary.sh is broken"
fi
chmod +x "$TGT/.claude/hooks/boundary.sh"

echo "— template ↔ plugin drift —"
drift=0
for d in "$ROOT"/template/skills/*/; do
  name="$(basename "$d")"
  cmp -s "$d/SKILL.md" "$ROOT/skills/${name#cordon-}/SKILL.md" || drift=1
done
for f in "$ROOT"/template/hooks/*.sh; do
  cmp -s "$f" "$ROOT/hooks/$(basename "$f")" || drift=1
done
check "plugin copies match template (run scripts/sync-plugin.sh if not)" "[ $drift -eq 0 ]"

echo
echo "enforcement: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

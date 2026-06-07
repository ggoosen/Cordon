#!/usr/bin/env bash
# Cordon installer — copies the template into a target repo's .claude/ and
# stamps the governance posture into CLAUDE.md. Idempotent: re-running
# updates Cordon's files and leaves everything else alone.
#
# Usage:
#   ./install.sh [TARGET_DIR] [--posture enforce|guide] [--policy strict|guided]
#   curl -fsSL https://raw.githubusercontent.com/ggoosen/Cordon/main/install.sh | bash
#
# Defaults: TARGET_DIR=$PWD, --posture enforce, --policy strict.
set -euo pipefail

REPO_URL="https://github.com/ggoosen/Cordon.git"

err() { printf 'cordon install: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

TARGET="$PWD"
POSTURE="enforce"
POLICY="strict"

while [ $# -gt 0 ]; do
  case "$1" in
    --posture) POSTURE="${2:-}"; shift 2 ;;
    --policy) POLICY="${2:-}"; shift 2 ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) err "unknown flag: $1" ;;
    *) TARGET="$1"; shift ;;
  esac
done

case "$POSTURE" in enforce | guide) : ;; *) err "--posture must be enforce or guide" ;; esac
case "$POLICY" in strict | guided) : ;; *) err "--policy must be strict or guided" ;; esac

command -v jq >/dev/null 2>&1 || echo "cordon install: WARNING — jq is required by the hooks at runtime and was not found on PATH. Install it (brew install jq / apt install jq); without it every guarded tool call fails closed." >&2
git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 || err "$TARGET is not a git repository (Cordon's isolation is built on git worktrees)"
TARGET="$(git -C "$TARGET" rev-parse --show-toplevel)"

# Locate the template: next to this script, or bootstrap a clone (curl|bash).
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || true)"
CLEANUP=""
if [ -z "$SRC" ] || [ ! -d "$SRC/template" ]; then
  command -v git >/dev/null 2>&1 || err "git is required"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/cordon-install.XXXXXX")"
  CLEANUP="$TMP"
  echo "Fetching Cordon ($REPO_URL)…"
  git clone --quiet --depth 1 "$REPO_URL" "$TMP/cordon" || err "could not clone $REPO_URL"
  SRC="$TMP/cordon"
fi
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT
T="$SRC/template"
[ -d "$T" ] || err "template directory not found at $T"

echo "Installing Cordon into $TARGET (posture: $POSTURE, policy: $POLICY)"

mkdir -p "$TARGET/.claude/hooks" "$TARGET/.claude/skills" "$TARGET/.claude/statusline"

# settings.json — back up a pre-existing non-Cordon settings file rather than
# silently clobbering it.
DEST_SETTINGS="$TARGET/.claude/settings.json"
if [ -f "$DEST_SETTINGS" ] && ! cmp -s "$T/settings.json" "$DEST_SETTINGS"; then
  if ! grep -q 'cordon' "$DEST_SETTINGS" 2>/dev/null; then
    cp "$DEST_SETTINGS" "$DEST_SETTINGS.pre-cordon"
    note "existing settings.json backed up to .claude/settings.json.pre-cordon — merge anything you need back in"
  fi
fi
cp "$T/settings.json" "$DEST_SETTINGS"
note ".claude/settings.json (sandbox + deny rules + hooks + statusline)"

# hooks, skills, statusline
cp "$T"/hooks/*.sh "$TARGET/.claude/hooks/"
chmod +x "$TARGET/.claude/hooks/"*.sh
note ".claude/hooks/ (boundary, enforce-isolation, audit, lib)"

for s in "$T"/skills/*/; do
  name="$(basename "$s")"
  mkdir -p "$TARGET/.claude/skills/$name"
  cp "$s/SKILL.md" "$TARGET/.claude/skills/$name/SKILL.md"
done
note ".claude/skills/ (/cordon-review /cordon-accept /cordon-discard /cordon-status)"

cp "$T/statusline/statusline.sh" "$TARGET/.claude/statusline/statusline.sh"
chmod +x "$TARGET/.claude/statusline/statusline.sh"
note ".claude/statusline/statusline.sh"

# policy config
sed "s/^CORDON_POLICY=.*/CORDON_POLICY=$POLICY/" "$T/cordon.config" >"$TARGET/.claude/cordon.config"
note ".claude/cordon.config (CORDON_POLICY=$POLICY)"

# CLAUDE.md governance stamp — replace our marked block if present, else append.
GOV="$T/governance/CLAUDE.$POSTURE.md"
CM="$TARGET/CLAUDE.md"
BEGIN='<!-- BEGIN CORDON GOVERNANCE'
END='<!-- END CORDON GOVERNANCE -->'
if [ -f "$CM" ] && grep -q "$BEGIN" "$CM"; then
  awk -v gov="$GOV" -v begin="$BEGIN" -v end="$END" '
    index($0, begin) { skip = 1; while ((getline line < gov) > 0) print line; close(gov); next }
    index($0, end) { skip = 0; next }
    !skip { print }
  ' "$CM" >"$CM.tmp" && mv "$CM.tmp" "$CM"
  note "CLAUDE.md (replaced existing Cordon governance block, posture: $POSTURE)"
elif [ -f "$CM" ]; then
  { printf '\n'; cat "$GOV"; } >>"$CM"
  note "CLAUDE.md (appended Cordon governance block, posture: $POSTURE — your existing content untouched)"
else
  cp "$GOV" "$CM"
  note "CLAUDE.md (created, posture: $POSTURE)"
fi

# .gitignore wiring (idempotent)
GI="$TARGET/.gitignore"
touch "$GI"
for line in ".claude/worktrees/" ".claude/cordon-audit.jsonl" ".claude/settings.local.json"; do
  grep -qxF "$line" "$GI" || echo "$line" >>"$GI"
done
note ".gitignore (worktrees, audit log, local settings)"

cat <<EOF

Done. Next steps:
  1. Review and commit the new files (CLAUDE.md, .claude/, .gitignore) so the
     whole team gets the same rails — they travel into every worktree.
  2. Run 'claude' once in $TARGET to accept workspace trust, then start
     isolated sessions with:  claude --worktree
  3. The flow: work → /cordon-review → /cordon-accept or /cordon-discard.

Honesty note: Cordon contains accidents and misbehavior, not a determined
adversary. Read the README's security callout before trusting it further.
EOF

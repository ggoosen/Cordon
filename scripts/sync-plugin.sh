#!/usr/bin/env bash
# Regenerate the plugin-scoped copies (skills/, hooks/*.sh) from template/.
# template/ is the single source of truth; run this after editing it (CI
# runs it too and fails on drift — see tests/test-enforcement.sh).
#
# Plugin skill directories are RENAMED (cordon-review → review) so the
# namespaced commands read /cordon:review rather than /cordon:cordon-review.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

rm -rf "$ROOT/skills"
mkdir -p "$ROOT/skills"
for d in "$ROOT"/template/skills/*/; do
  name="$(basename "$d")"
  short="${name#cordon-}"
  mkdir -p "$ROOT/skills/$short"
  cp "$d/SKILL.md" "$ROOT/skills/$short/SKILL.md"
done

mkdir -p "$ROOT/hooks"
rm -f "$ROOT"/hooks/*.sh
cp "$ROOT"/template/hooks/*.sh "$ROOT/hooks/"
chmod +x "$ROOT"/hooks/*.sh

echo "plugin copies synced from template/"

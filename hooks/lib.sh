#!/usr/bin/env bash
# Cordon shared hook helpers.
#
# Sourced by boundary.sh / enforce-isolation.sh / audit.sh. Must stay
# compatible with bash 3.2 (macOS default). Every function here is exercised
# by tests/test-boundary.sh — change with the tests open.

# Fail closed: a hook that crashes must block, not silently allow.
# (Claude Code treats exit codes other than 0/2 as NON-blocking errors.)
cordon_fail_closed() {
  echo "Cordon: internal hook error — failing closed. ($*)" >&2
  exit 2
}

cordon_require() { # $1 = binary the hook cannot work without
  command -v "$1" >/dev/null 2>&1 || cordon_fail_closed "required tool '$1' not found"
}

# Lexically normalize a path: make absolute against $2, resolve '.', '..'
# and duplicate slashes. No filesystem access, no symlink resolution
# (see cordon_resolve for that). Runs in a subshell so `set -f` (glob off,
# needed for the IFS-split loop) cannot leak.
cordon_abspath() ( # $1 = path, $2 = base dir for relative paths
  set -f
  p="$1"
  case "$p" in
    /*) : ;;
    ~/*) p="${HOME}/${p#\~/}" ;;
    '~') p="$HOME" ;;
    *) p="$2/$p" ;;
  esac
  out=''
  IFS='/'
  for seg in $p; do
    case "$seg" in
      '' | '.') : ;;
      '..') out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  printf '%s' "${out:-/}"
)

# Resolve the existing portion of a path through symlinks, so a symlinked
# parent dir can't smuggle a write outside the boundary, and so macOS
# /var → /private/var style links compare consistently. Walks up to the
# deepest EXISTING ancestor, canonicalizes it (cd + pwd -P), and re-appends
# the not-yet-existing remainder lexically. (A symlinked *leaf file* is
# still possible — documented limitation; the permission system's own
# symlink checks and the sandbox back this up.)
cordon_resolve() { # $1 = lexically-normalized absolute path
  local path="$1" suffix="" real
  while [ "$path" != "/" ] && [ ! -d "$path" ]; do
    suffix="/${path##*/}$suffix"
    path="${path%/*}"
    [ -n "$path" ] || path="/"
  done
  real="$(cd "$path" 2>/dev/null && pwd -P)" || real="$path"
  printf '%s%s' "${real%/}" "$suffix"
}

# Is $1 (a cwd) inside a linked git worktree? Detects both Claude Code's
# .claude/worktrees/ layout and manually-created linked worktrees.
cordon_in_worktree() { # $1 = cwd
  local gd
  case "$1" in */.claude/worktrees/*) return 0 ;; esac
  gd="$(git -C "$1" rev-parse --git-dir 2>/dev/null)" || return 1
  case "$gd" in */worktrees/*) return 0 ;; esac
  return 1
}

# The boundary root for a session: the toplevel of whatever checkout (main
# or worktree) the cwd is in. Falls back to the cwd outside a git repo.
cordon_boundary_root() { # $1 = cwd
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$1"
}

# The MAIN checkout root, even when called from inside a worktree. Used so
# the audit trail survives a discarded worktree.
cordon_main_root() { # $1 = cwd
  local common
  common="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || {
    printf '%s' "$1"
    return
  }
  case "$common" in
    /*) : ;;
    *) common="$(cordon_abspath "$common" "$1")" ;;
  esac
  printf '%s' "${common%/.git}"
}

# Active policy: strict (default) or guided.
#   strict — file mutations outside an isolated worktree are denied.
#   guided — warn and shepherd, but allow work in the main checkout.
# Env var wins; then .claude/cordon.config; then strict.
cordon_policy() {
  local root f v
  if [ -n "${CORDON_POLICY:-}" ]; then
    printf '%s' "$CORDON_POLICY"
    return
  fi
  root="${CLAUDE_PROJECT_DIR:-$PWD}"
  f="$root/.claude/cordon.config"
  if [ -f "$f" ]; then
    v="$(sed -n 's/^CORDON_POLICY=//p' "$f" | head -n 1 | tr -d '[:space:]')"
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return
    fi
  fi
  printf 'strict'
}

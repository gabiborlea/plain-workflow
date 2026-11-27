#!/usr/bin/env bash
# Removes a setup made by the old install.sh: the skill links, the CLAUDE.md block and
# the settings.json hook. Run it before you install the plugin, or the rules load twice.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SKILLS_DST="$CLAUDE_DIR/skills"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
SETTINGS="$CLAUDE_DIR/settings.json"
CONFIG="$CLAUDE_DIR/plain-workflow.json"

HOOK_TAG='plain-speak-reminder'

BEGIN_MARK='<!-- BEGIN plain-workflow -->'
END_MARK='<!-- END plain-workflow -->'

DRY_RUN=0
STAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'EOF'
uninstall.sh — remove an install.sh setup of plain-workflow from ~/.claude

Run it before you install the plugin. Otherwise the rules and the hook load twice.

  ./uninstall.sh              remove
  ./uninstall.sh --dry-run    print every action, change nothing

Backups made by install.sh are left in place.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

say() { printf '  %-12s %s\n' "$1" "$2"; }
run() { if [ "$DRY_RUN" -eq 1 ]; then return 0; fi; "$@"; }

echo "plain-workflow uninstall"
echo "  target $CLAUDE_DIR"
echo

echo "skills"
removed=0

for src in "$SKILLS_SRC"/*/; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  src="${src%/}"
  dst="$SKILLS_DST/$name"

  if [ ! -L "$dst" ]; then
    # Not a symlink, or absent. Either way it is not ours to remove.
    say "skip" "$name (not a link from this repo)"
    continue
  fi

  if [ "$(readlink "$dst")" != "$src" ]; then
    say "skip" "$name (links elsewhere)"
    continue
  fi

  say "remove" "$name"
  run rm "$dst"
  removed=$((removed + 1))
done

echo
echo "CLAUDE.md"

if [ -f "$CLAUDE_MD" ] && grep -qF "$BEGIN_MARK" "$CLAUDE_MD"; then
  say "strip" "block and markers"
  if [ "$DRY_RUN" -eq 0 ]; then
    cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$STAMP"
    tmp="$(mktemp)"
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      $0==b { skip=1; next }
      $0==e { skip=0; next }
      !skip { print }
    ' "$CLAUDE_MD" > "$tmp"
    mv "$tmp" "$CLAUDE_MD"
    say "backup" "$(basename "$CLAUDE_MD").bak.$STAMP"
  fi
else
  say "skip" "no block found"
fi

echo
echo "hook (UserPromptSubmit)"

if ! command -v jq >/dev/null 2>&1; then
  say "skip" "jq not found — remove the hook by hand in $SETTINGS"
elif [ ! -f "$SETTINGS" ]; then
  say "skip" "no settings.json"
elif ! jq -e --arg tag "$HOOK_TAG" '
  [ (.hooks.UserPromptSubmit // [])[] | (.hooks // [])[] |
    select((.command // "") | test($tag)) ] | length > 0
' "$SETTINGS" >/dev/null 2>&1; then
  say "skip" "hook not found"
else
  say "remove" "plain-speak-reminder.sh"
  if [ "$DRY_RUN" -eq 0 ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$STAMP"
    tmp="$(mktemp)"
    # Drop the tagged entry, then drop UserPromptSubmit and hooks if they end up empty,
    # so an otherwise-untouched settings.json goes back to its original shape.
    jq --arg tag "$HOOK_TAG" '
      .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select(
          ((.hooks // []) | map(.command // "") | any(test($tag))) | not
        )))
      | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    say "backup" "$(basename "$SETTINGS").bak.$STAMP"
  fi
fi

echo
echo "config"
if [ -f "$CONFIG" ]; then
  # Your reviewer choice is yours. Keep it so a reinstall does not re-prompt.
  say "keep" "$CONFIG (delete it by hand to reset the reviewer)"
else
  say "skip" "no config"
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run — nothing changed"
else
  echo "done — $removed link$([ "$removed" -eq 1 ] || echo s) removed, hook and block stripped"
fi

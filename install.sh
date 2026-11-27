#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
BLOCK_SRC="$REPO_DIR/CLAUDE-BLOCK.md"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SKILLS_DST="$CLAUDE_DIR/skills"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
SETTINGS="$CLAUDE_DIR/settings.json"
# Backups must live OUTSIDE skills/. Claude Code scans every directory in there and
# would register a backup as a second, duplicate skill.
BACKUP_DIR="$CLAUDE_DIR/.plain-workflow-backups"

HOOK_CMD="$REPO_DIR/hooks/plain-speak-reminder.sh"
HOOK_TAG='plain-speak-reminder'

CONFIG="$CLAUDE_DIR/plain-workflow.json"
CONFIG_EXAMPLE="$REPO_DIR/config.example.json"

BEGIN_MARK='<!-- BEGIN plain-workflow -->'
END_MARK='<!-- END plain-workflow -->'

DRY_RUN=0
CHECK=0
REVIEWER=""
STAMP="$(date +%Y%m%d-%H%M%S)"
DRIFT=0

usage() {
  cat <<'EOF'
install.sh — link the plain-workflow skills into ~/.claude

  ./install.sh                     install or update
  ./install.sh --reviewer <name>   set the safe-review engine, skip the prompt
  ./install.sh --dry-run           print every action, change nothing
  ./install.sh --check             exit 0 if current, 1 if not
  ./install.sh --help

Reviewer values:
  auto                          pick the best engine present at run time
  pr-review-toolkit:review-pr   full multi-agent sweep
  code-review                   the built-in code-review skill
  builtin                       safe-review's own narrow pass, no dependency

Env:
  CLAUDE_DIR   target config dir (default: ~/.claude)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --check)      CHECK=1 ;;
    --reviewer)   shift; [ $# -gt 0 ] || { echo "--reviewer needs a value" >&2; exit 2; }; REVIEWER="$1" ;;
    --reviewer=*) REVIEWER="${1#--reviewer=}" ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '  %-12s %s\n' "$1" "$2"; }
run()  { if [ "$DRY_RUN" -eq 1 ] || [ "$CHECK" -eq 1 ]; then return 0; fi; "$@"; }

[ -d "$SKILLS_SRC" ]     || { echo "no skills/ dir at $SKILLS_SRC" >&2; exit 1; }
[ -f "$BLOCK_SRC" ]      || { echo "no CLAUDE-BLOCK.md at $BLOCK_SRC" >&2; exit 1; }
[ -x "$HOOK_CMD" ]       || { echo "hook not executable: $HOOK_CMD" >&2; exit 1; }
[ -f "$CONFIG_EXAMPLE" ] || { echo "no config.example.json at $CONFIG_EXAMPLE" >&2; exit 1; }

echo "plain-workflow"
echo "  repo   $REPO_DIR"
echo "  target $CLAUDE_DIR"
echo

# --- preflight ---------------------------------------------------------------
# These are runtime needs of the skills, not of this script. A missing one is a
# warning, never a hard stop: 4 of the 6 skills still work without any of them.
echo "preflight"
have() { command -v "$1" >/dev/null 2>&1; }

if have jq;      then say "ok" "jq"; else say "MISSING" "jq — install.sh cannot wire the hook or the config"; fi
if have git;     then say "ok" "git"; else say "MISSING" "git — safe-review cannot find a fork point"; fi
if have python3; then say "ok" "python3"; else say "warn" "python3 — the simple-english linter will not run"; fi

if have gh; then
  if gh auth status >/dev/null 2>&1; then
    say "ok" "gh (authenticated)"
  else
    say "warn" "gh present but not authenticated — run: gh auth login"
  fi
else
  say "MISSING" "gh — explain-ticket, safe-review and answer-review need it"
fi

echo

run mkdir -p "$SKILLS_DST"

# --- skills ------------------------------------------------------------------
echo "skills"
linked=0

for src in "$SKILLS_SRC"/*/; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  src="${src%/}"
  dst="$SKILLS_DST/$name"

  if [ -L "$dst" ]; then
    current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then
      say "ok" "$name"
      continue
    fi
    say "relink" "$name  (was $current)"
    DRIFT=1
    run rm "$dst"
  elif [ -e "$dst" ]; then
    # A real file or directory is in the way. Never delete it.
    say "backup" "$name -> .plain-workflow-backups/$name.$STAMP"
    DRIFT=1
    run mkdir -p "$BACKUP_DIR"
    run mv "$dst" "$BACKUP_DIR/$name.$STAMP"
  else
    say "link" "$name"
    DRIFT=1
  fi

  run ln -s "$src" "$dst"
  linked=$((linked + 1))
done

# A renamed or deleted skill leaves its old symlink behind, pointing at a path that no
# longer exists. Claude Code would still try to load it. Only links into this repo are
# touched, so nothing the user made by hand is at risk.
for dst in "$SKILLS_DST"/*; do
  [ -L "$dst" ] || continue
  target="$(readlink "$dst")"
  case "$target" in
    "$SKILLS_SRC"/*)
      if [ ! -e "$target" ]; then
        say "prune" "$(basename "$dst") (target no longer in the repo)"
        DRIFT=1
        run rm "$dst"
      fi
      ;;
  esac
done

echo

# --- CLAUDE.md block ---------------------------------------------------------
echo "CLAUDE.md"

if [ ! -f "$CLAUDE_MD" ]; then
  say "create" "$CLAUDE_MD"
  DRIFT=1
  if [ "$DRY_RUN" -eq 0 ] && [ "$CHECK" -eq 0 ]; then
    { printf '%s\n' "$BEGIN_MARK"; cat "$BLOCK_SRC"; printf '%s\n' "$END_MARK"; } > "$CLAUDE_MD"
  fi
elif grep -qF "$BEGIN_MARK" "$CLAUDE_MD" && grep -qF "$END_MARK" "$CLAUDE_MD"; then
  existing="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0==b{f=1;next} $0==e{f=0} f' "$CLAUDE_MD")"
  if [ "$existing" = "$(cat "$BLOCK_SRC")" ]; then
    say "ok" "block is current"
  else
    say "update" "block changed, replacing between markers"
    DRIFT=1
    if [ "$DRY_RUN" -eq 0 ] && [ "$CHECK" -eq 0 ]; then
      cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$STAMP"
      tmp="$(mktemp)"
      awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v blk="$BLOCK_SRC" '
        $0==b { print; while ((getline l < blk) > 0) print l; close(blk); skip=1; next }
        $0==e { skip=0; print; next }
        !skip { print }
      ' "$CLAUDE_MD" > "$tmp"
      mv "$tmp" "$CLAUDE_MD"
      say "backup" "$(basename "$CLAUDE_MD").bak.$STAMP"
    fi
  fi
else
  say "append" "block with markers"
  DRIFT=1
  if [ "$DRY_RUN" -eq 0 ] && [ "$CHECK" -eq 0 ]; then
    cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$STAMP"
    { printf '\n%s\n' "$BEGIN_MARK"; cat "$BLOCK_SRC"; printf '%s\n' "$END_MARK"; } >> "$CLAUDE_MD"
    say "backup" "$(basename "$CLAUDE_MD").bak.$STAMP"
  fi
fi

echo

# --- UserPromptSubmit hook ---------------------------------------------------
echo "hook (UserPromptSubmit)"

if ! command -v jq >/dev/null 2>&1; then
  say "skip" "jq not found — install jq, then re-run"
  DRIFT=1
elif [ -f "$SETTINGS" ] && ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  say "error" "$SETTINGS is not valid JSON — fix it, then re-run"
  DRIFT=1
else
  if [ -f "$SETTINGS" ]; then
    installed="$(jq -r --arg tag "$HOOK_TAG" '
      [ (.hooks.UserPromptSubmit // [])[] | (.hooks // [])[] |
        select((.command // "") | test($tag)) | .command ] | .[0] // ""
    ' "$SETTINGS")"
  else
    installed=""
  fi

  if [ "$installed" = "$HOOK_CMD" ]; then
    say "ok" "hook is current"
  else
    if [ -n "$installed" ]; then
      say "update" "hook path changed (was $installed)"
    else
      say "add" "plain-speak-reminder.sh"
    fi
    DRIFT=1
    if [ "$DRY_RUN" -eq 0 ] && [ "$CHECK" -eq 0 ]; then
      # Only back up a file that already held something. A fresh install would
      # otherwise leave a .bak containing nothing but {}.
      settings_existed=1
      if [ ! -f "$SETTINGS" ]; then
        settings_existed=0
        echo '{}' > "$SETTINGS"
      else
        cp "$SETTINGS" "$SETTINGS.bak.$STAMP"
      fi
      tmp="$(mktemp)"
      # Strip any entry tagged plain-speak-reminder first, so a changed repo path
      # replaces the old hook instead of stacking a second one.
      jq --arg cmd "$HOOK_CMD" --arg tag "$HOOK_TAG" '
        .hooks //= {}
        | .hooks.UserPromptSubmit //= []
        | .hooks.UserPromptSubmit |= map(select(
            ((.hooks // []) | map(.command // "") | any(test($tag))) | not
          ))
        | .hooks.UserPromptSubmit += [{hooks: [{type: "command", command: $cmd, timeout: 5}]}]
      ' "$SETTINGS" > "$tmp"
      mv "$tmp" "$SETTINGS"
      if [ "$settings_existed" -eq 1 ]; then
        say "backup" "$(basename "$SETTINGS").bak.$STAMP"
      else
        say "create" "$(basename "$SETTINGS")"
      fi
    fi
  fi
fi

echo

# --- review engine config ----------------------------------------------------
echo "config (safe-review engine)"

plugin_enabled() {
  [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg p "$1" '
    (.enabledPlugins // {}) | to_entries
    | any(.value == true and (.key | startswith($p + "@")))
  ' "$SETTINGS" >/dev/null 2>&1
}

# Seed from config.example.json so new keys (jira, and whatever comes later) always
# reach a fresh config instead of being silently absent.
write_config() {
  jq --arg r "$1" '.reviewer = $r' "$CONFIG_EXAMPLE" > "$CONFIG"
}

if [ -f "$CONFIG" ]; then
  cur="$(jq -r '.reviewer // "auto"' "$CONFIG" 2>/dev/null || echo "?")"
  if [ "$cur" = "?" ]; then
    say "error" "$CONFIG is not valid JSON — fix it or delete it"
    DRIFT=1
  else
    say "ok" "reviewer = $cur"

    # One-time reshape of the old nested layout. `jira.keys` and `ste.strict_keys` were
    # two lists naming the same projects; they collapse into one prefix -> mode map.
    if jq -e 'has("jira") or has("ste")' "$CONFIG" >/dev/null 2>&1; then
      say "migrate" "jira{} + ste{} -> jira_host + jira_keys"
      DRIFT=1
      if [ "$DRY_RUN" -eq 0 ] && [ "$CHECK" -eq 0 ]; then
        cp "$CONFIG" "$CONFIG.bak.$STAMP"
        tmp="$(mktemp)"
        jq '
          (.ste.strict_keys // []) as $strict
          | .jira_host = (.jira_host // .jira.host // "")
          | .jira_keys = (
              .jira_keys // (
                (.jira.keys // [])
                | map({key: ., value: (if IN($strict[]) then "strict" else "flavored" end)})
                | from_entries
              )
            )
          | del(.jira, .ste)
        ' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
        say "backup" "$(basename "$CONFIG").bak.$STAMP"
      fi
    fi

    # Additive only: `example * config` deep-merges, and the right side wins, so keys a
    # newer config.example.json introduced appear while every value the user set stays.
    merged="$(jq -S --slurpfile ex "$CONFIG_EXAMPLE" '$ex[0] * .' "$CONFIG")"
    if [ "$merged" != "$(jq -S . "$CONFIG")" ]; then
      added="$(jq -rn --slurpfile ex "$CONFIG_EXAMPLE" --slurpfile c "$CONFIG" \
        '($ex[0] | keys) - ($c[0] | keys) | join(", ")')"
      say "update" "adding config key(s): ${added:-nested defaults}"
      DRIFT=1
      if [ "$DRY_RUN" -eq 0 ] && [ "$CHECK" -eq 0 ]; then
        tmp="$(mktemp)"
        jq --slurpfile ex "$CONFIG_EXAMPLE" '$ex[0] * .' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
      fi
    fi
  fi
elif [ -n "$REVIEWER" ]; then
  say "create" "reviewer = $REVIEWER (from --reviewer)"
  DRIFT=1
  if [ "$DRY_RUN" -eq 0 ] && [ "$CHECK" -eq 0 ]; then write_config "$REVIEWER"; fi
elif [ "$DRY_RUN" -eq 1 ] || [ "$CHECK" -eq 1 ]; then
  say "create" "reviewer = <prompt on real install>"
  DRIFT=1
elif [ ! -t 0 ]; then
  # No terminal (CI, piped install). Prompting would hang, so take the safe default.
  say "create" "reviewer = auto (no terminal, not prompting)"
  DRIFT=1
  write_config "auto"
else
  plugin_enabled "pr-review-toolkit" && tk="available" || tk="NOT installed"
  plugin_enabled "code-review"       && cr="available" || cr="NOT installed"

  echo
  echo "  Which engine should /safe-review run before applying its 3 gates?"
  echo
  printf '    1) auto                          pick the best present at run time\n'
  printf '    2) pr-review-toolkit:review-pr   full multi-agent sweep      [%s]\n' "$tk"
  printf '    3) code-review                   lighter single pass         [%s]\n' "$cr"
  printf '    4) builtin                       no dependency, fastest      [always]\n'
  printf '    5) other                         name your own\n'
  echo
  echo "  Pick a number, or paste any skill, agent, or slash-command name."
  ans=""
  read -r -p "  choice [1]: " ans || true
  case "${ans:-1}" in
    1|"") REVIEWER="auto" ;;
    2)    REVIEWER="pr-review-toolkit:review-pr" ;;
    3)    REVIEWER="code-review" ;;
    4)    REVIEWER="builtin" ;;
    5)    REVIEWER=""
          while [ -z "$REVIEWER" ]; do
            read -r -p "  skill, agent, or command name: " REVIEWER || REVIEWER="auto"
          done ;;
    # A bare number outside 1-5 is a slip, not a reviewer name. Do not save it.
    [0-9]*) echo "  no such choice: $ans" >&2; exit 2 ;;
    *)    REVIEWER="$ans" ;;
  esac
  echo
  say "create" "reviewer = $REVIEWER"
  DRIFT=1
  write_config "$REVIEWER"
fi

echo

# --- summary -----------------------------------------------------------------
if [ "$CHECK" -eq 1 ]; then
  if [ "$DRIFT" -eq 1 ]; then
    echo "not current — run ./install.sh"
    exit 1
  fi
  echo "current"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run — nothing changed"
  exit 0
fi

if [ "$DRIFT" -eq 0 ]; then
  echo "already current — nothing changed"
  exit 0
fi

echo "done — $linked skill$([ "$linked" -eq 1 ] || echo s) linked, CLAUDE.md block written, hook wired"
echo "reviewer   $(jq -r '.reviewer // "auto"' "$CONFIG" 2>/dev/null || echo auto)  (edit $CONFIG to change)"
echo "restart Claude Code, or open /hooks once, to pick up the changes"

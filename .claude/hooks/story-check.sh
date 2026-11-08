#!/bin/bash
# Stop hook: if files changed after STORY.md was last written, asks the agent to update it.
# Fires once per stop, costs nothing when STORY.md is current.

input=$(cat)
case "$input" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

changed=$(
  git status --porcelain --untracked-files=all |
    cut -c4- |
    sed -E 's/.* -> //; s/^"//; s/"$//' |
    grep -vE '^(STORY\.md|CLAUDE\.md|\.claude/|\.playwright-mcp/|build/)' |
    while IFS= read -r file; do
      if [ -f "$file" ] && { [ ! -f STORY.md ] || [ "$file" -nt STORY.md ]; }; then
        echo "$file"
      fi
    done |
    head -5
)

[ -z "$changed" ] && exit 0

{
  echo "These files changed after the last STORY.md update:"
  echo "$changed"
  echo "If the change is relevant, update STORY.md following the rules at its top."
  echo "If it is not relevant, run: touch STORY.md"
} >&2
exit 2

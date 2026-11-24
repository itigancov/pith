#!/bin/sh
# PreToolUse hook: main changes only through pull requests.
# Blocks `git commit` while on main and any `git push` that targets main.
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

case "$cmd" in
  *"git "*) ;;
  *) exit 0 ;;
esac

# The repo the command acts on: `git -C <dir>`, else a leading `cd <dir> &&`, else the hook's cwd.
dir=$(printf '%s' "$cmd" | sed -nE 's/.*git +-C +"?([^" ]+)"?.*/\1/p')
[ -n "$dir" ] || dir=$(printf '%s' "$cmd" | sed -nE 's/^ *cd +"?([^" &;]+)"? *(&&|;).*/\1/p')
case "$dir" in
  "") dir=${cwd:-.} ;;
  /*) ;;
  *) dir="${cwd:-.}/$dir" ;;
esac
branch=$(git -C "$dir" branch --show-current 2>/dev/null)

if printf '%s' "$cmd" | grep -Eq 'git( +-[^ ]+( +[^ -][^ ]*)?)* +commit\b' && [ "$branch" = main ]; then
  echo "Blocked: no commits on main. Work in a worktree branch and open a pull request." >&2
  exit 2
fi

if printf '%s' "$cmd" | grep -Eq 'git( +-[^ ]+( +[^ -][^ ]*)?)* +push\b'; then
  if [ "$branch" = main ] || printf '%s' "$cmd" | grep -Eq '(^|[ :/])main( |$)'; then
    echo "Blocked: no pushes to main. Push the feature branch and open a pull request." >&2
    exit 2
  fi
fi
exit 0

#!/bin/bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
current_dir=$(basename "$cwd")
git_info=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" -c core.filesRefLockTimeout=0 branch --show-current 2>/dev/null || echo "detached")
    if ! git -C "$cwd" -c core.filesRefLockTimeout=0 diff-index --quiet HEAD -- 2>/dev/null; then
        dirty="*"
    else
        dirty=""
    fi
    git_info=" $(printf '\033[35mon\033[0m') $(printf '\033[31m%s%s\033[0m' "$branch" "$dirty")"
fi
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
if [ -n "$remaining" ]; then
    remaining_int=$(printf "%.0f" "$remaining")
    if [ "$remaining_int" -gt 50 ]; then
        context_color="\033[32m"
    elif [ "$remaining_int" -gt 20 ]; then
        context_color="\033[33m"
    else
        context_color="\033[31m"
    fi
    context_info=" $(printf "${context_color}[%d%% ctx]\033[0m" "$remaining_int")"
fi
printf '\033[36m%s\033[0m%s%s' "$current_dir" "$git_info" "$context_info"


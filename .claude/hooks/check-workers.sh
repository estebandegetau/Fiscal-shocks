#!/usr/bin/env bash
# Report-only check for stray crew/callr R worker processes.
#
# Wired as a PostToolUse(Bash) hook in .claude/settings.local.json. It NEVER
# kills anything — it only prints a warning when the count of matching worker
# processes exceeds THRESHOLD, and is silent otherwise (so it does not spam
# output after ordinary Bash calls).
#
# Background: orphaned crew/renv/callr R workers accumulate after pipeline runs
# on WSL2 and slow the machine. This surfaces them so the user can clean up.
#
# Override the threshold with CLAUDE_WORKER_THRESHOLD (default 4).

set -euo pipefail

THRESHOLD="${CLAUDE_WORKER_THRESHOLD:-4}"

# Match only R worker processes (executable R/Rscript) whose args mention a
# parallel-worker backend. Requiring the R binary avoids matching unrelated
# shells whose command line merely contains the word "crew"/"callr"/"mirai"
# (e.g. the Bash call that triggered this hook). `|| true` keeps exit 0.
matches="$(ps -eo pid=,ppid=,comm=,args= 2>/dev/null \
  | awk '$3 ~ /^(R|Rscript|exec\/R)$/ && $0 ~ /crew|callr|mirai/ { print }' || true)"

if [ -z "$matches" ]; then
  exit 0
fi

count="$(printf '%s\n' "$matches" | grep -c .)"

if [ "$count" -le "$THRESHOLD" ]; then
  exit 0
fi

echo "⚠️  $count stray crew/callr/mirai R worker process(es) detected (threshold $THRESHOLD)."
echo "   PID / PPID / cmd:"
# Trim the command to keep output short.
printf '%s\n' "$matches" \
  | awk '{ cmd=""; for (i=4;i<=NF && i<=9;i++) cmd=cmd" "$i; printf "   %s %s%s\n", $1, $2, cmd }'
echo "   To clean up after pipeline runs, inspect and kill orphans manually (e.g. kill <PID>)."
exit 0

#!/bin/sh
# Says whether a pull request may be merged into main. It is ready when:
# - the four CI jobs succeeded on its exact head, and no other check is red;
# - the last review verdict is APPROVED and quotes the tree of that head (CLAUDE.md, step 5).
# It waits while jobs run, and stops if the head moves. Only the main session runs it: agents
# never watch CI (docs/lessons.md).
#
#   sh scripts/merge-ready.sh <pull request number>
#
# Exit 0: ready. Exit 1: not ready, with the reason. Exit 2: cannot check (usage, gh or git).
# MERGE_READY_INTERVAL is the number of seconds between two reads: 60 by default, at least 10,
# so that GitHub's API limit is not used up. MERGE_READY_TIMEOUT is the wait in all, in seconds:
# 3600 by default. Neither may exceed 999999.
set -u
export LC_ALL=C GH_PROMPT_DISABLED=1
exec </dev/null

cannot() { echo "Error: cannot check: $1" >&2; exit 2; }
not_ready() { echo "not ready: $1" >&2; exit 1; }
usage() { echo "usage: sh scripts/merge-ready.sh <pull request number>" >&2; exit 2; }

case "${1:-}" in '' | *[!0-9]*) usage ;; esac
pr=$1
interval=${MERGE_READY_INTERVAL:-60}
timeout=${MERGE_READY_TIMEOUT:-3600}
case "$interval" in '' | *[!0-9]*) cannot "MERGE_READY_INTERVAL is not a number of seconds" ;; esac
case "$timeout" in '' | *[!0-9]*) cannot "MERGE_READY_TIMEOUT is not a number of seconds" ;; esac
# Six digits at most, so that the shell's arithmetic and [ never overflow.
[ ${#interval} -le 6 ] || cannot "MERGE_READY_INTERVAL is over 999999 seconds"
[ ${#timeout} -le 6 ] || cannot "MERGE_READY_TIMEOUT is over 999999 seconds"
[ "$interval" -ge 10 ] || cannot "MERGE_READY_INTERVAL is under 10 seconds"

# The four jobs of .github/workflows/ci.yml that protect main.
# Separated by | : awk -v takes no newline.
jobs='Repository rules|Test (x86_64-unknown-linux-musl)|Test (x86_64-pc-windows-gnu)|Test (aarch64-apple-darwin)'

head=$(gh pr view "$pr" --json headRefOid --jq .headRefOid) || cannot "gh pr view failed"
[ -n "$head" ] || cannot "pull request #$pr has no head"
tree=$(git rev-parse --verify --quiet "$head^{tree}") ||
    cannot "the head $head is not in this repository (run git fetch)"

# The last verdict is the last comment that quotes a reviewed tree (CLAUDE.md, step 5). Its
# first line says ", round <n>: APPROVED" followed by "." or a space (as in ": APPROVED with two
# minor points"), and no "CHANGES NEEDED". It quotes one tree only. It is read before the wait
# and again after it, so that a verdict posted meanwhile counts.
check_verdict() {
    verdict=$(gh pr view "$pr" --json comments \
        --jq '[.comments[] | select(.body | contains("Reviewed tree `"))] | last | .body // ""') ||
        cannot "gh pr view failed"
    [ -n "$verdict" ] || not_ready "no verdict comment quotes a reviewed tree on pull request #$pr"
    first=$(printf '%s\n' "$verdict" | head -n 1)
    case "$first" in
        *"CHANGES NEEDED"*) not_ready "the last verdict is not approved: $first" ;;
    esac
    printf '%s\n' "$first" | grep -Eq ', round [0-9]+: APPROVED[ .]' ||
        not_ready "the last verdict is not approved: $first"
    quoted=$(printf '%s\n' "$verdict" | grep -o 'Reviewed tree `[^`]*`' | sort -u)
    [ "$(printf '%s\n' "$quoted" | wc -l)" -eq 1 ] ||
        not_ready "the last verdict quotes more than one tree"
    [ "$quoted" = "Reviewed tree \`$tree\`" ] ||
        not_ready "the approved tree is not the tree of the head $head ($tree)"
}
check_verdict

start=$(date +%s) || cannot "date failed"
while :; do
    rows=$(gh pr view "$pr" --json headRefOid,statusCheckRollup --jq '.headRefOid,
        (.statusCheckRollup[] | [.__typename, (.name // .context // ""),
            (.conclusion // .state // ""), (.startedAt // "")] | @tsv)') ||
        cannot "gh pr view failed"
    now=$(printf '%s\n' "$rows" | head -n 1)
    [ "$now" = "$head" ] || not_ready "head moved from $head to $now"
    # Only the latest attempt of each check counts. An attempt not started yet (no value, no
    # time) is the latest. A finished one with no time is the oldest. On equal times the later
    # line wins. A required job is green only on SUCCESS; another check also on NEUTRAL or
    # SKIPPED. Empty, PENDING, EXPECTED, QUEUED and IN_PROGRESS mean still running; gh gives a
    # running CheckRun an empty conclusion, so QUEUED and IN_PROGRESS are only a guard. Any
    # other value is red. A check with no name is named "(no name)".
    state=$(printf '%s\n' "$rows" | sed 1d | awk -F '\t' -v jobs="$jobs" '
        NF >= 2 {
            k = ($2 == "" ? "(no name)" : $2); v = $3; t = $4
            fresh = (v == "" && (t == "" || t == "0001-01-01T00:00:00Z"))
            if (!(k in seen) || fresh || (!bestfresh[k] && t >= when[k])) {
                seen[k] = 1; val[k] = v; when[k] = t; bestfresh[k] = fresh
            }
        }
        END {
            n = split(jobs, req, "|")
            for (i = 1; i <= n; i++) {
                need[req[i]] = 1
                if (!(req[i] in seen)) print "running\t" req[i]
            }
            for (k in seen) {
                v = val[k]
                if (v == "" || v == "PENDING" || v == "EXPECTED" || v == "QUEUED" || v == "IN_PROGRESS")
                    print "running\t" k
                else if (v == "SUCCESS" || (!(k in need) && (v == "NEUTRAL" || v == "SKIPPED")))
                    continue
                else
                    print "red\t" k
            }
        }') || cannot "awk failed"
    red=$(printf '%s\n' "$state" | awk -F '\t' '$1 == "red" { print $2; exit }')
    [ -z "$red" ] || not_ready "red: $red"
    running=$(printf '%s\n' "$state" | awk -F '\t' '$1 == "running" { printf "%s%s", s, $2; s = ", " }')
    [ -n "$running" ] || break
    now_s=$(date +%s) || cannot "date failed"
    elapsed=$(( now_s - start ))
    [ "$elapsed" -lt "$timeout" ] || not_ready "timed out after ${timeout}s; still running: $running"
    sleep "$interval"
done
check_verdict

echo "ready: PR #$pr, head $head, tree $tree: the four CI jobs succeeded, no check is red, and" \
    "the last verdict approves this tree."

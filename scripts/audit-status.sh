#!/bin/sh
# Coherence status of the repository: what the periodic audit and every session start look at.
#   scripts/audit-status.sh                    report (always exit 0)
#   scripts/audit-status.sh --gate-commit      exit 1 if an audit is due before this commit (pre-commit)
#   scripts/audit-status.sh --gate-push [REV]  exit 1 if REV (default HEAD) is past the audit cadence
#                                              (pre-push with the pushed commit; CI with the PR head)
# Exit 2 when git cannot answer: never a silent pass.
# An audit is a commit that changes only files under docs/audits/ (see CLAUDE.md, "Coherence
# audits"); a commit mixing a report with other changes does not count as one.
set -u
AUDIT_EVERY=3

cd "$(git rev-parse --show-toplevel)" || exit 2

mode=${1:-}
tip=HEAD
[ "$mode" = --gate-push ] && [ -n "${2:-}" ] && tip=$2
git rev-parse --verify --quiet "$tip^{commit}" >/dev/null || { echo "Error: not a commit: $tip" >&2; exit 2; }

last_audit=""
candidates=$(git log --first-parent --format=%H "$tip" -- docs/audits) || exit 2
for c in $candidates; do
    others=$(git diff-tree --no-commit-id --name-only -r "$c" | grep -v '^docs/audits/' || true)
    if [ -z "$others" ]; then last_audit=$c; break; fi
done
if [ -n "$last_audit" ]; then
    since=$(git rev-list --count --first-parent "$last_audit..$tip") || exit 2
else
    # No audit yet: count every commit except the repository's initial one.
    total=$(git rev-list --count --first-parent "$tip") || exit 2
    since=$(( total > 0 ? total - 1 : 0 ))
fi

case "$mode" in
    --gate-commit)
        [ "$since" -lt "$AUDIT_EVERY" ] && exit 0
        # The audit commit itself (only docs/audits/ staged) is always allowed.
        others=$(git diff --cached --name-only | grep -v '^docs/audits/' || true)
        [ -z "$others" ] && exit 0
        echo "Error: $since commits since the last coherence audit (limit $AUDIT_EVERY)." >&2
        echo "Run the coherence-auditor agent and commit its report alone in docs/audits/ first." >&2
        exit 1 ;;
    --gate-push)
        [ "$since" -le "$AUDIT_EVERY" ] && exit 0
        echo "Error: $since commits since the last coherence audit (limit $AUDIT_EVERY) at $tip." >&2
        exit 1 ;;
    "") ;;
    *) echo "usage: $0 [--gate-commit | --gate-push [REV]]" >&2; exit 2 ;;
esac

section() { printf '\n== %s\n' "$1"; }

section "Audit cadence"
echo "commits since last audit: $since (audit every $AUDIT_EVERY)"
if [ -n "$last_audit" ]; then
    echo "last audit: $(git log -1 --format='%h %ad %s' --date=short "$last_audit")"
else
    echo "last audit: none yet"
fi
[ "$since" -ge "$AUDIT_EVERY" ] && echo "AUDIT DUE"

section "Unfinished local work"
dirty=$(git status --porcelain)
[ -n "$dirty" ] && { echo "uncommitted changes:"; printf '%s\n' "$dirty"; } || echo "working tree clean"
stashes=$(git stash list)
[ -n "$stashes" ] && { echo "stashes:"; printf '%s\n' "$stashes"; }
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    echo "branch $(git rev-parse --abbrev-ref HEAD): $(git rev-list --count '@{u}..HEAD') unpushed, $(git rev-list --count 'HEAD..@{u}') not pulled"
else
    echo "branch $(git rev-parse --abbrev-ref HEAD): no upstream"
fi
unmerged=$(git branch --no-merged main 2>/dev/null)
[ -n "$unmerged" ] && { echo "local branches not merged into main:"; printf '%s\n' "$unmerged"; }
remote_unmerged=$(git branch -r --no-merged origin/main 2>/dev/null | grep -v 'origin/HEAD' || true)
[ -n "$remote_unmerged" ] && { echo "remote branches not merged into main:"; printf '%s\n' "$remote_unmerged"; }

section "Markers in code"
markers=$(grep -rnE 'TODO|FIXME|XXX|todo!\(|unimplemented!\(|#\[ignore' src tests 2>/dev/null | grep -v '^tests/fixtures/' || true)
[ -n "$markers" ] && printf '%s\n' "$markers" || echo "none"

section "GitHub"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    prs=$(gh pr list --state open --json number,title,isDraft,updatedAt,headRefName \
        --jq '.[] | "#\(.number) \(if .isDraft then "DRAFT" else "open" end) \(.headRefName) updated \(.updatedAt[:10]): \(.title)"' 2>/dev/null)
    [ -n "$prs" ] && { echo "open pull requests:"; printf '%s\n' "$prs"; } || echo "no open pull requests"
    runs=$(gh run list --branch main --limit 3 --json conclusion,status,displayTitle,createdAt \
        --jq '.[] | "\(.createdAt[:10]) \(.status)/\(.conclusion // "-"): \(.displayTitle)"' 2>/dev/null)
    [ -n "$runs" ] && { echo "last CI runs on main:"; printf '%s\n' "$runs"; } || echo "no CI runs on main"
else
    echo "gh not available or not logged in: pull requests and CI not checked"
fi

#!/bin/sh
# Coherence status of the repository: what the periodic audit and every session start look at.
#   scripts/audit-status.sh                    report (always exit 0)
#   scripts/audit-status.sh --gate-commit      exit 1 if an audit is due before this commit (pre-commit)
#   scripts/audit-status.sh --gate-push [REV]  exit 1 if REV (default HEAD) is past the audit cadence
#                                              (pre-push with the pushed commit; CI with the PR head)
# Every commit not reachable from the last audit counts, also those brought in by a merge.
# Exit 2 when git cannot answer: never a silent pass.
# An audit is a non-merge commit that only adds files under docs/audits/ (see CLAUDE.md, "Coherence
# audits"); a commit mixing a report with other changes, or deleting one, does not count.
set -u
AUDIT_EVERY=5

cd "$(git rev-parse --show-toplevel)" || exit 2

mode=${1:-}
tip=HEAD
[ "$mode" = --gate-push ] && [ -n "${2:-}" ] && tip=$2
git rev-parse --verify --quiet "$tip^{commit}" >/dev/null || { echo "Error: not a commit: $tip" >&2; exit 2; }
if [ "$mode" != "" ] && [ "$(git rev-parse --is-shallow-repository)" != false ]; then
    echo "Error: shallow clone, the commits since the last audit cannot be counted." >&2; exit 2
fi

last_audit=""
candidates=$(git log --format=%H "$tip" -- docs/audits) || exit 2
for c in $candidates; do
    # A merge commit has an empty diff-tree output, so it never counts as an audit.
    changes=$(git diff-tree --root --no-commit-id -r --name-status "$c") || exit 2
    [ -n "$changes" ] || continue
    # An audit only adds report files: a deletion or any other change does not count.
    others=$(printf '%s\n' "$changes" | grep -vE '^A[[:space:]]+docs/audits/' || true)
    if [ -z "$others" ]; then last_audit=$c; break; fi
done
if [ -n "$last_audit" ]; then
    since=$(git rev-list --count "$last_audit..$tip") || exit 2
else
    # No audit yet: count every commit except the repository's initial one.
    total=$(git rev-list --count "$tip") || exit 2
    since=$(( total > 0 ? total - 1 : 0 ))
fi

case "$mode" in
    --gate-commit)
        [ "$since" -lt "$AUDIT_EVERY" ] && exit 0
        # The audit commit itself (only new files under docs/audits/ staged) is always allowed.
        staged=$(git diff --cached --name-status) || exit 2
        others=$(printf '%s\n' "$staged" | grep -vE '^A[[:space:]]+docs/audits/' || true)
        [ -n "$staged" ] && [ -z "$others" ] && exit 0
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

if [ "$(git config core.hooksPath)" != .githooks ]; then
    echo "HOOKS NOT ENABLED in this clone: nothing stops a commit or push with personal data."
    echo "Run: git config core.hooksPath .githooks"
fi

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
# Full ref names: a tag called "main" (or like the branch) must not stand in for the branch.
current=$(git symbolic-ref -q HEAD | sed 's|^refs/heads/||'); current=${current:-HEAD (detached)}
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    echo "branch $current: $(git rev-list --count '@{u}..HEAD') unpushed, $(git rev-list --count 'HEAD..@{u}') not pulled"
else
    echo "branch $current: no upstream"
fi
if git rev-parse -q --verify refs/heads/main >/dev/null; then
    unmerged=$(git for-each-ref --no-merged refs/heads/main --format='  %(refname)' refs/heads | sed 's|refs/heads/||')
    [ -n "$unmerged" ] && { echo "local branches not merged into main:"; printf '%s\n' "$unmerged"; }
else
    echo "no local branch main: unmerged local branches not checked"
fi
if git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
    remote_unmerged=$(git for-each-ref --no-merged refs/remotes/origin/main --format='  %(refname)' refs/remotes | sed 's|refs/remotes/||' | grep -v '/HEAD$' || true)
    [ -n "$remote_unmerged" ] && { echo "remote branches not merged into main:"; printf '%s\n' "$remote_unmerged"; }
elif git remote | grep -qx origin; then
    echo "no origin/main: unmerged remote branches not checked"
fi

section "Markers in code"
markers=$(grep -rnE 'TODO|FIXME|XXX|todo!\(|unimplemented!\(|#\[ignore' src tests 2>/dev/null | grep -v '^tests/fixtures/' || true)
[ -n "$markers" ] && printf '%s\n' "$markers" || echo "none"

section "Leftovers (scripts/cleanup.sh --plan; run scripts/cleanup.sh to remove the local ones)"
sh scripts/cleanup.sh --plan || true

section "GitHub"
# The report only reads: gh never prompts and never reads standard input.
export GH_PROMPT_DISABLED=1
exec </dev/null
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    # Only collaborators may open PRs, issues and comments; GitHub limits this to 6 months.
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
    expires=$(gh api "repos/$repo/interaction-limits" --jq '.expires_at // ""' 2>/dev/null | cut -c1-10)
    warn_from=$(date -u -v+30d +%Y-%m-%d 2>/dev/null || date -u -d '+30 days' +%Y-%m-%d)
    if [ -z "$expires" ]; then
        echo "INTERACTION LIMIT NOT ACTIVE: anyone can open PRs and issues. Renew it on GitHub:"
        echo "  Settings > Moderation options > Interaction limits > Limit to repository collaborators (6 months)"
    elif [ "$expires" != "$warn_from" ] && [ "$(printf '%s\n%s\n' "$expires" "$warn_from" | sort | head -n 1)" = "$expires" ]; then
        echo "INTERACTION LIMIT EXPIRES on $expires: renew it on GitHub (Settings > Moderation options)."
    fi
    prs=$(gh pr list --state open --json number,title,isDraft,updatedAt,headRefName \
        --jq '.[] | "#\(.number) \(if .isDraft then "DRAFT" else "open" end) \(.headRefName) updated \(.updatedAt[:10]): \(.title)"' 2>/dev/null)
    [ -n "$prs" ] && { echo "open pull requests:"; printf '%s\n' "$prs"; } || echo "no open pull requests"
    failing=$(gh pr list --state open --json number,statusCheckRollup \
        --jq '.[] | select([.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length > 0) | "#\(.number) failing: \([.statusCheckRollup[] | select(.conclusion == "FAILURE") | .name] | join(", "))"' 2>/dev/null)
    [ -n "$failing" ] && { echo "RED CHECKS on open pull requests:"; printf '%s\n' "$failing"; }
    runs=$(gh run list --branch main --limit 3 --json conclusion,status,displayTitle,createdAt \
        --jq '.[] | "\(.createdAt[:10]) \(.status)/\(.conclusion // "-"): \(.displayTitle)"' 2>/dev/null)
    [ -n "$runs" ] && { echo "last CI runs on main:"; printf '%s\n' "$runs"; } || echo "no CI runs on main"
else
    echo "gh not available or not logged in: pull requests and CI not checked"
fi

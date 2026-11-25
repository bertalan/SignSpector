#!/bin/sh
# Coherence status of the repository: what the periodic audit and every session start look at.
#   scripts/audit-status.sh                    report (always exit 0)
#   scripts/audit-status.sh --gate-commit      exit 1 if an audit is due before this commit (pre-commit)
#   scripts/audit-status.sh --gate-push [REV]  exit 1 if REV (default HEAD) is past the audit cadence
#                                              (pre-push with the pushed commit; CI with the PR head)
# Every commit not reachable from the last audit counts, also those brought in by a merge.
# Exit 2 when git cannot answer: never a silent pass.
# An audit is a non-merge commit that only adds files under docs/audits/ (see CLAUDE.md, "How do
# we keep long work from drifting?"); a commit mixing a report with other changes, or deleting
# one, does not count.
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

# The hooks run from this repository's .githooks folder, named relative or by absolute path.
hooks_path=$(git config core.hooksPath || true)
hooks_ok=no
if [ "$hooks_path" = .githooks ]; then
    hooks_ok=yes
else
    case "$hooks_path" in
        /*|[A-Za-z]:/*|[A-Za-z]:\\*)
            # Same folder by identity (-ef), not by path text. On Windows runners the temporary
            # folder may be reached by a short 8.3 name (RUNNER~1) on one side and the long name
            # on the other.
            hooks_top=$(git rev-parse --show-toplevel)
            [ -d "$hooks_path" ] && [ -d "$hooks_top/.githooks" ] &&
                [ "$hooks_path" -ef "$hooks_top/.githooks" ] && hooks_ok=yes ;;
    esac
fi
if [ "$hooks_ok" != yes ]; then
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

section "Rust"
# The pinned version (rust-toolchain.toml) is moved by hand; say when a newer stable exists.
# rustup check needs a "stable" toolchain installed. It prints one line per toolchain:
# "up to date: X" or "update available: X -> Y" (rustup 1.29), "Up to date : X" (older releases).
# The first line of the stable channel is read.
pinned=$(sed -n "s/^[[:space:]]*channel[[:space:]]*=[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p" rust-toolchain.toml 2>/dev/null | head -n 1)
latest=$(rustup check 2>/dev/null </dev/null | sed -n \
    -e 's/^stable-.* -> \([0-9][0-9.]*\).*/\1/p' \
    -e 's/^stable-.* [Uu]p to date *: *\([0-9][0-9.]*\).*/\1/p' | head -n 1)
if [ -z "$pinned" ]; then
    echo "pinned Rust version not found in rust-toolchain.toml"
elif ! printf '%s\n' "$pinned" | grep -qx '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*'; then
    echo "pinned Rust $pinned is not x.y.z; see rust-toolchain.toml"
elif [ -z "$latest" ]; then
    echo "Rust release not checked (rustup check failed, or no stable toolchain: rustup toolchain install stable)"
elif [ "$latest" = "$pinned" ]; then
    echo "pinned Rust $pinned is the latest stable"
elif [ "$(printf '%s\n%s\n' "$pinned" "$latest" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)" = "$latest" ]; then
    echo "NEWER RUST STABLE: $latest (pinned: $pinned); see rust-toolchain.toml"
else
    echo "pinned Rust $pinned; latest stable reported by rustup: $latest"
fi

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
# tests/corpus/ and tests/out/ hold real and extracted documents: their files are never read,
# not only hidden from the output.
# Any case: on macOS and Windows tests/Corpus is tests/corpus (find -ipath is not POSIX).
markers=$(find src tests -path 'tests/[Cc][Oo][Rr][Pp][Uu][Ss]' -prune \
    -o -path 'tests/[Oo][Uu][Tt]' -prune \
    -o -path tests/fixtures -prune -o -type f \
    -exec grep -nHE 'TODO|FIXME|XXX|todo!\(|unimplemented!\(|#\[ignore' {} + 2>/dev/null || true)
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
    # A failing gh api is said: it is not a missing limit.
    limit_read=yes
    expires=$(gh api "repos/$repo/interaction-limits" --jq '.expires_at // ""' 2>/dev/null) ||
        limit_read=no
    expires=$(printf '%s' "$expires" | cut -c1-10)
    warn_from=$(date -u -v+30d +%Y-%m-%d 2>/dev/null || date -u -d '+30 days' +%Y-%m-%d)
    if [ "$limit_read" = no ]; then
        echo "interaction limit not read (gh api failed)"
    elif [ -z "$expires" ]; then
        echo "INTERACTION LIMIT NOT ACTIVE: anyone can open PRs and issues. Renew it on GitHub:"
        echo "  Settings > Moderation options > Interaction limits > Limit to repository collaborators (6 months)"
    elif [ "$expires" != "$warn_from" ] && [ "$(printf '%s\n%s\n' "$expires" "$warn_from" | sort | head -n 1)" = "$expires" ]; then
        echo "INTERACTION LIMIT EXPIRES on $expires: renew it on GitHub (Settings > Moderation options)."
    fi
    if prs=$(gh pr list --state open --json number,title,isDraft,updatedAt,headRefName \
        --jq '.[] | "#\(.number) \(if .isDraft then "DRAFT" else "open" end) \(.headRefName) "
            + "updated \(.updatedAt[:10]): \(.title)"' 2>/dev/null); then
        if [ -n "$prs" ]; then
            echo "open pull requests:"; printf '%s\n' "$prs"
        else
            echo "no open pull requests"
        fi
    else
        echo "open pull requests not read (gh pr list failed)"
    fi
    # Everything that is not green is red (owner's decision, 2026-11-24). gh gives one line per
    # attempt of a check: PR number, type, workflow, name, conclusion of a check run, state of
    # a commit status, start time.
    # The rule is an allowlist, compared whole:
    # - A check run is red when its conclusion is not empty and not SUCCESS, NEUTRAL or SKIPPED.
    # - A commit status is red when its state is not empty and not SUCCESS, PENDING or EXPECTED.
    # - A row of any other type is red when its conclusion or its state is not empty and not one
    #   of the green values of either list (SUCCESS, NEUTRAL, SKIPPED, PENDING, EXPECTED).
    # So STALE, and any value GitHub adds later, is red. Running and pending checks are not red
    # yet. NEUTRAL and SKIPPED stay green because the owner's rule is read as GitHub's branch
    # protection reads it: skipped and neutral jobs pass.
    # The workflow is the name of the workflow of a check run. It is empty for a check that is
    # not from a workflow, and for a commit status. Two checks of the same name in different
    # workflows are different checks. gh gives no event for them.
    # Only the latest attempt of each check counts (owner's decision, 2026-11-25): a failure
    # re-run green is not red. A check is one PR, type, workflow and name. The latest attempt
    # is the one that started last.
    # The start times are ISO 8601 in UTC and are compared as strings. That is correct for
    # GitHub's times, which have whole seconds.
    # An attempt not started yet (no conclusion, no state, and no time or GitHub's zero time)
    # is the latest. A finished attempt with no time is older than any attempt with a time.
    # On equal times, and between attempts with no time, the later line wins.
    if rollup=$(gh pr list --state open --json number,statusCheckRollup \
        --jq '.[] | .number as $n | .statusCheckRollup[]?
            | [$n, .__typename, (.workflowName // ""), (.name // .context // ""),
               (.conclusion // ""), (.state // ""), (.startedAt // "")] | @tsv' 2>/dev/null); then
        failing=$(printf '%s\n' "$rollup" |
        awk -F '\t' '
            {
                notime = ($7 == "" || $7 ~ /^0001-/)
                if (!notime) at = $7
                else if ($5 == "" && $6 == "") at = "9999"
                else at = ""
                key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
                if (!(key in when)) {
                    keys[++k] = key; pr[key] = $1
                    name[key] = ($3 != "" ? $3 " / " : "") ($4 != "" ? $4 : "(no name)")
                }
                else if (at < when[key]) next
                when[key] = at
                red[key] = ($2 == "CheckRun" && $5 != "" && $5 !~ /^(SUCCESS|NEUTRAL|SKIPPED)$/) ||
                           ($2 == "StatusContext" && $6 != "" &&
                            $6 !~ /^(SUCCESS|PENDING|EXPECTED)$/) ||
                           ($2 != "CheckRun" && $2 != "StatusContext" &&
                            (($5 != "" && $5 !~ /^(SUCCESS|NEUTRAL|SKIPPED|PENDING|EXPECTED)$/) ||
                             ($6 != "" && $6 !~ /^(SUCCESS|NEUTRAL|SKIPPED|PENDING|EXPECTED)$/)))
            }
            END {
                for (i = 1; i <= k; i++) {
                    key = keys[i]
                    if (!red[key]) continue
                    p = pr[key]
                    if (!(p in list)) { order[++n] = p; list[p] = name[key] }
                    else list[p] = list[p] ", " name[key]
                }
                for (i = 1; i <= n; i++) print "#" order[i] " failing: " list[order[i]]
            }')
        [ -n "$failing" ] && { echo "RED CHECKS on open pull requests:"; printf '%s\n' "$failing"; }
    else
        echo "checks not read (gh pr list failed)"
    fi
    if runs=$(gh run list --branch main --limit 3 --json conclusion,status,displayTitle,createdAt \
        --jq '.[] | "\(.createdAt[:10]) \(.status)/\(.conclusion // "-"): "
            + "\(.displayTitle)"' 2>/dev/null); then
        if [ -n "$runs" ]; then
            echo "last CI runs on main:"; printf '%s\n' "$runs"
        else
            echo "no CI runs on main"
        fi
    else
        echo "CI runs not read (gh run list failed)"
    fi
else
    echo "gh not available or not logged in: pull requests and CI not checked"
fi

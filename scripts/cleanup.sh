#!/bin/sh
# Removes local leftovers after a coherence audit (CLAUDE.md, "Coherence audits").
#   scripts/cleanup.sh                     lists the plan; at a terminal, asks to type the number
#                                          of items to remove; without a terminal removes nothing
#   scripts/cleanup.sh --plan              lists the plan only, never asks (session report)
#   scripts/cleanup.sh --yes --expect <n>  removes without asking, only if the plan has exactly
#                                          <n> items (scripts); otherwise exit 2, nothing removed
# Same confirmation rule as the tool itself (R29, R30): no --apply.
# Local only: nothing on GitHub is ever deleted (remote branches, pull requests); what is found
# there is reported for the user to handle.
#
# Removed: untracked, not ignored, unambiguous junk (.DS_Store, *.orig, *.rej); local branches
# already merged into main and not checked out anywhere.
# Never removed, only listed: worktrees (any state), backups and editor files (*.bak, *.swp,
# *~), other untracked files, unmerged branches. Never touched: tracked files, anything in an
# ignored folder, and always tests/corpus/ (real documents), tests/out/, target/; main.
set -uf
export LC_ALL=C

usage() { echo "usage: $0 [--plan | --yes --expect <n>]" >&2; exit 2; }
plan_only=0; yes=0; expect=""
while [ $# -gt 0 ]; do
    case "$1" in
        --plan) plan_only=1 ;;
        --yes) yes=1 ;;
        --expect) [ $# -ge 2 ] || usage; expect=$2; shift ;;
        *) usage ;;
    esac
    shift
done
[ "$yes" -eq 1 ] && [ -z "$expect" ] && { echo "Error: --yes needs --expect <n>." >&2; exit 2; }
[ -n "$expect" ] && [ "$yes" -eq 0 ] && { echo "Error: --expect needs --yes." >&2; exit 2; }
case "$expect" in ""|*[!0-9]*) [ -n "$expect" ] && usage ;; esac

# Inside a git hook the index may be a temporary one: tracked files would look untracked.
if [ -n "${GIT_INDEX_FILE:-}" ] || [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
    echo "Error: run cleanup.sh by hand, not from a git hook (GIT_INDEX_FILE, GIT_DIR or GIT_WORK_TREE set)." >&2
    exit 2
fi

top=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$top" ] || { echo "Error: not inside a git repository." >&2; exit 2; }
cd "$top" || exit 2
main=main
status=0
nl='
'

# 1. Worktrees: listed only. Removing one can lose ignored files or commits on no branch.
first=1
git worktree list --porcelain | while IFS= read -r line; do
    case "$line" in worktree\ *) ;; *) continue ;; esac
    if [ "$first" -eq 1 ]; then first=0; continue; fi    # the main working tree
    echo "worktree (not removed; remove it by hand when done): ${line#worktree }"
done

# 2. Plan: local branches merged into main (not main, not checked out anywhere).
checked_out=$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
branches=""
# for-each-ref on refs/heads: no "(HEAD detached at ...)" pseudo-entry.
for b in $(git for-each-ref --merged "$main" --format='%(refname:short)' refs/heads); do
    [ "$b" = "$main" ] && continue
    case "$nl$checked_out$nl" in *"$nl$b$nl"*) echo "keep branch (checked out in a worktree): $b"; continue ;; esac
    echo "would remove local branch (merged): $b"
    branches="$branches$b$nl"
done
for b in $(git for-each-ref --no-merged "$main" --format='%(refname:short)' refs/heads); do
    echo "keep local branch (not merged): $b"
done

# 3. Plan: untracked junk outside ignored folders; the rest listed for review.
junk='(^|/)(\.DS_Store|[^/]*\.(orig|rej))$'
files=""
old_ifs=$IFS
IFS=$nl
# Folders with real documents and build output are never touched, even if .gitignore lacks them.
# -i: on case-insensitive file systems (macOS, Windows) tests/Corpus/ is the same folder.
for f in $(git -c core.quotepath=off ls-files --others --exclude-standard | grep -Eiv '^(tests/corpus|tests/out|target)/'); do
    if printf '%s\n' "$f" | grep -Eq "$junk"; then
        echo "would remove junk file: $f"
        files="$files$f$nl"
    else
        echo "review (untracked, not removed): $f"
    fi
done
IFS=$old_ifs

# 4. GitHub: reported only, never deleted from here.
# Full ref names: the short form of refs/remotes/origin/HEAD is just "origin".
for b in $(git branch -r --merged "$main" --format='%(refname)' | grep -v -e '/HEAD$' -e "/$main\$" | sed 's|^refs/remotes/||'); do
    echo "on GitHub, merged (not deleted here; delete it on GitHub if no longer needed): $b"
done
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh pr list --state open --draft --json number,title,updatedAt \
        --jq '.[] | "on GitHub, draft PR (not closed here): #\(.number) updated \(.updatedAt[:10]): \(.title)"' 2>/dev/null || true
fi

# 5. Confirmation: the number of items, typed at a terminal or given with --yes --expect.
n=$(printf '%s%s' "$branches" "$files" | grep -c .)
if [ "$n" -eq 0 ]; then echo "nothing to remove"; exit 0; fi
[ "$plan_only" -eq 1 ] && exit 0
if [ "$yes" -eq 1 ]; then
    [ "$expect" = "$n" ] || { echo "Error: the plan has $n items, --expect says $expect: nothing removed." >&2; exit 2; }
elif [ -t 0 ]; then
    printf 'Type %s to remove these %s items (anything else keeps them): ' "$n" "$n"
    read -r answer || answer=""
    [ "$answer" = "$n" ] || { echo "nothing removed"; exit 0; }
else
    echo "nothing removed: no terminal. To remove these $n items: scripts/cleanup.sh --yes --expect $n"
    exit 0
fi

IFS=$nl
for b in $branches; do
    if git branch -q -d "$b"; then echo "removed local branch (merged): $b"; else status=1; fi
done
for f in $files; do
    if rm -f -- "$f"; then echo "removed junk file: $f"; else status=1; fi
done
IFS=$old_ifs
exit "$status"

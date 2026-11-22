#!/bin/sh
# Removes local leftovers after a coherence audit (CLAUDE.md, "Coherence audits").
#   scripts/cleanup.sh          dry run: lists what would be removed and what needs review
#   scripts/cleanup.sh --apply  removes it
# Local only: nothing on GitHub is ever deleted (remote branches, pull requests); what is found
# there is reported for the user to handle.
#
# Removed: untracked, not ignored, unambiguous junk (.DS_Store, *.orig, *.rej); local branches
# already merged into main and not checked out anywhere.
# Never removed, only listed: worktrees (any state), backups and editor files (*.bak, *.swp,
# *~), other untracked files, unmerged branches. Never touched: tracked files, anything in an
# ignored folder (tests/corpus/ holds real documents, target/ the build), main.
set -uf
export LC_ALL=C

apply=0
case "${1:-}" in
    "") ;;
    --apply) apply=1 ;;
    *) echo "usage: $0 [--apply]" >&2; exit 2 ;;
esac

# Inside a git hook the index may be a temporary one: tracked files would look untracked.
if [ -n "${GIT_INDEX_FILE:-}" ] || [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
    echo "Error: run cleanup.sh by hand, not from a git hook (GIT_INDEX_FILE/GIT_DIR set)." >&2
    exit 2
fi

cd "$(git rev-parse --show-toplevel)" || exit 2
main=main
verb="would remove"; [ "$apply" -eq 1 ] && verb="removed"
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

# 2. Local branches merged into main, not main, not checked out anywhere.
checked_out=$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
for b in $(git branch --merged "$main" --format='%(refname:short)'); do
    [ "$b" = "$main" ] && continue
    case "$nl$checked_out$nl" in *"$nl$b$nl"*) echo "keep branch (checked out in a worktree): $b"; continue ;; esac
    echo "$verb local branch (merged): $b"
    [ "$apply" -eq 1 ] && { git branch -q -d "$b" || status=1; }
done
for b in $(git branch --no-merged "$main" --format='%(refname:short)'); do
    echo "keep local branch (not merged): $b"
done

# 3. Untracked files outside ignored folders: junk is removed, the rest listed for review.
junk='(^|/)(\.DS_Store|[^/]*\.(orig|rej))$'
old_ifs=$IFS
IFS=$nl
for f in $(git -c core.quotepath=off ls-files --others --exclude-standard); do
    if printf '%s\n' "$f" | grep -Eq "$junk"; then
        echo "$verb junk file: $f"
        [ "$apply" -eq 1 ] && { rm -f -- "$f" || status=1; }
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

exit "$status"

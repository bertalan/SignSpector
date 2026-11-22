#!/bin/sh
# Removes local leftovers after a coherence audit (CLAUDE.md, "Coherence audits").
#   scripts/cleanup.sh          dry run: lists what would be removed and what needs review
#   scripts/cleanup.sh --apply  removes it
# Local only: nothing on GitHub is ever deleted (remote branches, pull requests); what is found
# there is reported for the user to handle.
# Removed: untracked junk files (*.orig *.rej *.bak *.swp *~ .DS_Store), worktrees with no
# uncommitted changes, local branches already merged into main.
# Never removed: tracked files, ignored build output (target/), other untracked files (they may
# be work in progress: listed for review), worktrees with changes, unmerged branches.
set -uf
export LC_ALL=C

apply=0
case "${1:-}" in
    "") ;;
    --apply) apply=1 ;;
    *) echo "usage: $0 [--apply]" >&2; exit 2 ;;
esac

cd "$(git rev-parse --show-toplevel)" || exit 2
main=main
verb="would remove"; [ "$apply" -eq 1 ] && verb="removed"
status=0
nl='
'

# 1. Worktrees (before branches: a branch checked out in a worktree cannot be deleted).
first=1
git worktree list --porcelain | while IFS= read -r line; do
    case "$line" in worktree\ *) ;; *) continue ;; esac
    path=${line#worktree }
    if [ "$first" -eq 1 ]; then first=0; continue; fi    # the main working tree
    if [ ! -d "$path" ]; then
        echo "stale worktree entry: $path"
        continue
    fi
    if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
        echo "keep worktree (uncommitted changes): $path"
        continue
    fi
    echo "$verb worktree: $path"
    [ "$apply" -eq 1 ] && { git worktree remove "$path" || echo "  could not remove $path" >&2; }
done
[ "$apply" -eq 1 ] && git worktree prune

# 2. Local branches merged into main, not checked out anywhere.
checked_out=$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
current=$(git rev-parse --abbrev-ref HEAD)
for b in $(git branch --merged "$main" --format='%(refname:short)'); do
    [ "$b" = "$main" ] && continue
    [ "$b" = "$current" ] && continue
    case "$nl$checked_out$nl" in *"$nl$b$nl"*) echo "keep branch (checked out in a worktree): $b"; continue ;; esac
    echo "$verb local branch (merged): $b"
    [ "$apply" -eq 1 ] && { git branch -q -d "$b" || status=1; }
done
for b in $(git branch --no-merged "$main" --format='%(refname:short)'); do
    echo "keep local branch (not merged): $b"
done

# 3. Untracked files: junk is removed, anything else is listed for review.
junk='(^|/)(\.DS_Store|[^/]*\.(orig|rej|bak|swp)|[^/]*~)$'
old_ifs=$IFS
IFS=$nl
for f in $(git -c core.quotepath=off ls-files --others | grep -v '^target/'); do
    if printf '%s\n' "$f" | grep -Eq "$junk"; then
        echo "$verb junk file: $f"
        [ "$apply" -eq 1 ] && { rm -f -- "$f" || status=1; }
    fi
done
for f in $(git -c core.quotepath=off ls-files --others --exclude-standard); do
    printf '%s\n' "$f" | grep -Eq "$junk" && continue
    echo "review (untracked, not removed): $f"
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

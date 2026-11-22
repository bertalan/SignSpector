#!/bin/sh
# Removes local leftovers after a coherence audit (CLAUDE.md, "Coherence audits").
#   scripts/cleanup.sh         removes the local leftovers listed below and says what it removed
#   scripts/cleanup.sh --plan  lists what it would remove and removes nothing (session report)
# No question is asked: only unambiguous junk files and branches already merged into main
# (their commits stay in main) are removed.
# Local only: nothing on GitHub is ever deleted. Merged remote branches stay there as history;
# draft pull requests are reported.
#
# Removed: untracked, not ignored, unambiguous junk (.DS_Store, *.orig, *.rej); local branches
# already merged into main and not checked out anywhere.
# Never removed, only listed: worktrees (any state), backups and editor files (*.bak, *.swp,
# *~), other untracked files, unmerged branches. Never touched: tracked files, anything in an
# ignored folder, and always tests/corpus/ (real documents), tests/out/, target/; main.
set -uf
export LC_ALL=C

usage() { echo "usage: $0 [--plan]" >&2; exit 2; }
plan_only=0
case "$#:${1:-}" in
    0:) ;;
    1:--plan) plan_only=1 ;;
    *) usage ;;
esac

# Inside a git hook the index may be a temporary one: tracked files would look untracked.
if [ -n "${GIT_INDEX_FILE:-}" ] || [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
    echo "Error: run cleanup.sh by hand, not from a git hook (GIT_INDEX_FILE, GIT_DIR or GIT_WORK_TREE set)." >&2
    exit 2
fi

top=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$top" ] || { echo "Error: not inside a git repository." >&2; exit 2; }
cd "$top" || exit 2
main=main
main_ref=refs/heads/$main   # full name: a tag called "main" must not stand in for the branch
git rev-parse -q --verify "refs/heads/$main" >/dev/null || { echo "Error: no local branch $main to compare with: nothing removed." >&2; exit 2; }
status=0
nl='
'
# "would remove" lines belong to the plan; a removal run prints only what it removed.
plan() { [ "$plan_only" -eq 1 ] && printf '%s\n' "$1"; return 0; }

# 1. Worktrees: listed only. Removing one can lose ignored files or commits on no branch.
first=1
git worktree list --porcelain | while IFS= read -r line; do
    case "$line" in worktree\ *) ;; *) continue ;; esac
    if [ "$first" -eq 1 ]; then first=0; continue; fi    # the main working tree
    echo "worktree (not removed; remove it by hand when done): ${line#worktree }"
done

# 2. Plan: local branches merged into main (not main, not checked out anywhere). A branch
# fast-forwarded into main and one just created at main look the same; neither holds a commit
# that main lacks, so removing either loses nothing.
checked_out=$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
here=$(git symbolic-ref -q HEAD | sed 's|^refs/heads/||')   # not --short: "heads/x" if a tag is x
branches=""
# for-each-ref on refs/heads: no "(HEAD detached at ...)" pseudo-entry.
# Full names, stripped by hand: the short form becomes "heads/x" when a tag is also called x.
for b in $(git for-each-ref --merged "$main_ref" --format='%(refname)' refs/heads | sed 's|^refs/heads/||'); do
    [ "$b" = "$main" ] && continue
    [ "$b" = "$here" ] && { echo "keep branch (checked out here): $b"; continue; }
    case "$nl$checked_out$nl" in *"$nl$b$nl"*) echo "keep branch (checked out in a worktree): $b"; continue ;; esac
    plan "would remove local branch (merged): $b"
    branches="$branches$b$nl"
done
for b in $(git for-each-ref --no-merged "$main_ref" --format='%(refname)' refs/heads | sed 's|^refs/heads/||'); do
    echo "keep local branch (not merged): $b"
done

# 3. Plan: untracked junk outside ignored folders; the rest listed for review.
junk='(^|/)(\.DS_Store|[^/]*\.(orig|rej))$'
files=""
old_ifs=$IFS
IFS=$nl
# Folders with real documents and build output are never touched, even if .gitignore lacks them.
# -i: on case-insensitive file systems (macOS, Windows) tests/Corpus/ is the same folder.
# "?: git quotes some names ("tests/corpus/a\"b"); those are not even printed.
for f in $(git -c core.quotepath=off ls-files --others --exclude-standard | grep -Eiv '^"?(tests/corpus|tests/out|target)/'); do
    # git quotes names with a backslash or a double quote ("a\\b.orig"): never removed.
    case "$f" in \"*) printf '%s\n' "review (special characters, not removed): $f"; continue ;; esac
    if printf '%s\n' "$f" | grep -Eq "$junk"; then
        plan "would remove junk file: $f"
        files="$files$f$nl"
    else
        printf '%s\n' "review (untracked, not removed): $f"
    fi
done
IFS=$old_ifs

# 4. GitHub: reported only, never deleted from here.
# Full ref names: the short form of refs/remotes/origin/HEAD is just "origin".
for b in $(git branch -r --merged "$main_ref" --format='%(refname)' | grep -v -e '/HEAD$' -e "/$main\$" | sed 's|^refs/remotes/||'); do
    echo "on GitHub, merged (kept, nothing is deleted on GitHub): $b"
done
# gh never asks anything: no prompts, no standard input.
if command -v gh >/dev/null 2>&1 && GH_PROMPT_DISABLED=1 gh auth status >/dev/null 2>&1 </dev/null; then
    GH_PROMPT_DISABLED=1 gh pr list --state open --draft --json number,title,updatedAt \
        --jq '.[] | "on GitHub, draft PR (not closed here): #\(.number) updated \(.updatedAt[:10]): \(.title)"' 2>/dev/null </dev/null || true
fi

# 5. Removal (unless --plan).
n=$(printf '%s%s' "$branches" "$files" | grep -c .)
if [ "$n" -eq 0 ]; then echo "nothing to remove"; exit 0; fi
[ "$plan_only" -eq 1 ] && exit 0

IFS=$nl
for b in $branches; do
    # -D, not -d: -d compares with HEAD or the upstream, not with main. Merged into main is
    # checked again just before deleting.
    if git merge-base --is-ancestor "refs/heads/$b" "refs/heads/$main" && git branch -q -D "$b" >/dev/null; then
        echo "removed local branch (merged): $b"
    else echo "keep branch (no longer merged into $main, or git refused): $b" >&2; status=1; fi
done
for f in $files; do
    if rm -f -- "$f"; then printf '%s\n' "removed junk file: $f"; else status=1; fi
done
IFS=$old_ifs
exit "$status"

#!/bin/sh
# Tests for scripts/cleanup.sh, in throw-away repositories: sh scripts/test-cleanup.sh
set -u
export LC_ALL=C

src=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
# Isolation: hooks run with GIT_INDEX_FILE and other GIT_* variables pointing at the real
# repository; the throw-away repositories below must never see them.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

passed=0
failed=0
ok()  { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAIL: $1" >&2; }
check() { if eval "$2"; then ok; else bad "$1"; fi; } # check <description> <shell condition>

rm -rf "$work/r" "$work/remote.git"
git init -q --bare "$work/remote.git"
mkdir -p "$work/r/scripts" && cd "$work/r" || exit 2
git init -q -b main
cp "$src/cleanup.sh" scripts/
printf '/target/\n' > .gitignore
echo tracked > kept.orig                      # tracked: never deleted, even with a junk name
git add -A && git commit -qm initial
git remote add origin "$work/remote.git" && git push -q origin main 2>/dev/null
git remote set-head origin main               # origin/HEAD exists in real clones

# Leftovers of every kind.
echo junk > a.orig; echo junk > b.rej; echo junk > c.bak; echo junk > 'd~'; echo junk > .DS_Store
mkdir -p sub && echo junk > sub/e.swp
echo "my notes" > notes.txt                   # unknown untracked file: user work, never deleted
mkdir -p target && echo build > target/x       # ignored build output: not touched
echo build > target/old.bak                  # junk-looking name inside target/: not touched
git switch -q -c old && echo o > o.txt && git add o.txt && git commit -qm old
git switch -q main && git merge -q --ff-only old  # "old" is merged
git push -q origin main old 2>/dev/null          # merged branch also on the remote
git switch -q -c wip && echo w > w.txt && git add w.txt && git commit -qm wip
git switch -q main                               # "wip" is not merged
git worktree add -q "$work/wt-clean" old 2>/dev/null
git worktree add -q -b dirty "$work/wt-dirty" main 2>/dev/null
echo change > "$work/wt-dirty/uncommitted.txt"

# Dry run: lists, deletes nothing.
out=$(sh scripts/cleanup.sh 2>&1); r=$?
check "dry run exits 0"                     '[ $r -eq 0 ]'
check "dry run lists junk files"            'printf "%s" "$out" | grep -q "a.orig"'
check "dry run lists merged branch"         'printf "%s" "$out" | grep -q "old"'
check "dry run lists unknown file for review" 'printf "%s" "$out" | grep -q "notes.txt"'
check "dry run deletes nothing"             '[ -f a.orig ] && [ -f sub/e.swp ] && git rev-parse -q --verify old >/dev/null && [ -d "$work/wt-clean" ]'

# Apply: local leftovers go, everything else stays.
out=$(sh scripts/cleanup.sh --apply 2>&1); r=$?
check "apply exits 0"                       '[ $r -eq 0 ]'
check "junk files removed"                  '[ ! -e a.orig ] && [ ! -e b.rej ] && [ ! -e c.bak ] && [ ! -e "d~" ] && [ ! -e .DS_Store ] && [ ! -e sub/e.swp ]'
check "tracked file kept"                   '[ -f kept.orig ]'
check "unknown untracked file kept"         '[ -f notes.txt ]'
check "ignored build output kept"           '[ -f target/x ] && [ -f target/old.bak ]'
check "merged local branch deleted"         '! git rev-parse -q --verify refs/heads/old >/dev/null'
check "unmerged branch kept"                'git rev-parse -q --verify refs/heads/wip >/dev/null'
check "clean worktree removed"              '[ ! -d "$work/wt-clean" ]'
check "dirty worktree kept"                 '[ -f "$work/wt-dirty/uncommitted.txt" ]'
check "dirty worktree reported as kept"     'printf "%s" "$out" | grep -q "keep worktree (uncommitted changes): .*wt-dirty"'
check "remote branch never deleted"         'git --git-dir="$work/remote.git" rev-parse -q --verify refs/heads/old >/dev/null'
check "remote merged branch reported"       'printf "%s" "$out" | grep -q "origin/old"'
check "origin/HEAD is not a branch"         '! printf "%s" "$out" | grep -Eq "merged.*: origin\$"'
check "unknown option refused"              '! sh scripts/cleanup.sh --force >/dev/null 2>&1'

echo "cleanup tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]

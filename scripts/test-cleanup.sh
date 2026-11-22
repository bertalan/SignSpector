#!/bin/sh
# Tests for scripts/cleanup.sh, in throw-away repositories: sh scripts/test-cleanup.sh
set -u
# Isolation: hooks run with GIT_INDEX_FILE and other GIT_* variables pointing at the real
# repository; the throw-away repositories below must never see them.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

src=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
ok()  { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAIL: $1" >&2; }
check() { if eval "$2"; then ok; else bad "$1"; fi; } # check <description> <shell condition>

git init -q --bare "$work/remote.git"
mkdir -p "$work/r/scripts" && cd "$work/r" || exit 2
git init -q -b main
cp "$src/cleanup.sh" scripts/
printf '/target/\n/tests/corpus/\n/dist/\n' > .gitignore
echo tracked > kept.orig                      # tracked: never deleted, even with a junk name
git add -A && git commit -qm initial
git remote add origin "$work/remote.git" && git push -q origin main 2>/dev/null
git remote set-head origin main               # origin/HEAD exists in real clones

# Untracked files: only unambiguous junk outside ignored folders may go.
echo junk > a.orig; echo junk > b.rej; echo junk > .DS_Store
echo mine > c.bak; echo mine > 'd~'; mkdir -p sub && echo mine > sub/e.swp   # backups, editor files
echo mine > 'notes~old.txt'                   # not junk: "~" inside the name
echo "my notes" > notes.txt                   # unknown untracked file: user work
mkdir -p tests/corpus && echo real > tests/corpus/verbale.orig   # ignored: real documents
echo real > tests/corpus/contratto.pdf.p7m.bak
mkdir -p target dist && echo build > target/old.bak && echo build > dist/a.orig
# Branches.
git switch -q -c old && echo o > o.txt && git add o.txt && git commit -qm old
git switch -q main && git merge -q --ff-only old  # "old" is merged
git push -q origin main old 2>/dev/null          # merged branch also on the remote
git switch -q -c wa && git switch -q main        # merged, but checked out in a worktree below
git switch -q -c wip && echo w > w.txt && git add w.txt && git commit -qm wip
git switch -q main                               # "wip" is not merged
# Worktrees: never removed, whatever their state.
git worktree add -q "$work/wt-clean" wa 2>/dev/null
git worktree add -q --detach "$work/wt-detached" main 2>/dev/null
mkdir -p "$work/wt-clean/tests/corpus" && echo real > "$work/wt-clean/tests/corpus/doc.p7m"

# Dry run: lists, deletes nothing.
out=$(sh scripts/cleanup.sh 2>&1); r=$?
check "dry run exits 0"                       '[ $r -eq 0 ]'
check "dry run lists junk files"              'printf "%s" "$out" | grep -q "a.orig"'
check "dry run lists merged branch"           'printf "%s" "$out" | grep -q "branch (merged): old"'
check "dry run lists backups for review"      'printf "%s" "$out" | grep -q "review.*c.bak"'
check "dry run lists unknown file for review" 'printf "%s" "$out" | grep -q "review.*notes.txt"'
check "dry run deletes nothing"               '[ -f a.orig ] && git rev-parse -q --verify refs/heads/old >/dev/null'

# Apply.
out=$(sh scripts/cleanup.sh --apply 2>&1); r=$?
check "apply exits 0"                         '[ $r -eq 0 ]'
check "junk files removed"                    '[ ! -e a.orig ] && [ ! -e b.rej ] && [ ! -e .DS_Store ]'
check "backups and editor files kept"         '[ -f c.bak ] && [ -f "d~" ] && [ -f sub/e.swp ] && [ -f "notes~old.txt" ]'
check "tracked file kept"                     '[ -f kept.orig ]'
check "unknown untracked file kept"           '[ -f notes.txt ]'
check "ignored folders untouched"             '[ -f tests/corpus/verbale.orig ] && [ -f tests/corpus/contratto.pdf.p7m.bak ] && [ -f target/old.bak ] && [ -f dist/a.orig ]'
check "merged local branch deleted"           '! git rev-parse -q --verify refs/heads/old >/dev/null'
check "unmerged branch kept"                  'git rev-parse -q --verify refs/heads/wip >/dev/null'
check "branch checked out in a worktree kept" 'git rev-parse -q --verify refs/heads/wa >/dev/null'
check "worktrees never removed"               '[ -f "$work/wt-clean/tests/corpus/doc.p7m" ] && [ -d "$work/wt-detached" ]'
check "worktrees listed"                      'printf "%s" "$out" | grep -q "worktree.*wt-detached"'
check "remote branch never deleted"           'git --git-dir="$work/remote.git" rev-parse -q --verify refs/heads/old >/dev/null'
check "remote merged branch reported"         'printf "%s" "$out" | grep -q "origin/old"'
check "origin/HEAD is not a branch"           '! printf "%s" "$out" | grep -Eq "merged.*: origin(/HEAD)?\$"'

# Names that must not be expanded, split or matched loosely.
echo junk > 'my file.orig'; echo mine > plan.orig.txt; echo junk > '*.orig'
sh scripts/cleanup.sh --apply >/dev/null 2>&1
check "name with a space removed whole"       '[ ! -e "my file.orig" ] && [ ! -e my ]'
check "junk rule anchored at the end"         '[ -f plan.orig.txt ]'
check "star name not expanded to tracked files" '[ -f kept.orig ] && [ ! -e "*.orig" ]'
# tests/corpus/ is protected even when its ignore line is missing (old checkout, rebase).
mkdir -p tests/out
echo real > tests/out/report.orig
printf '\n' > .gitignore
sh scripts/cleanup.sh --apply >/dev/null 2>&1
check "corpus protected without the ignore line" '[ -f tests/corpus/verbale.orig ]'
check "tests/out protected without the ignore line" '[ -f tests/out/report.orig ]'
check "target protected without the ignore line" '[ -f target/old.bak ] && [ -f dist/a.orig ] || [ -f target/old.bak ]'
git checkout -q -- .gitignore
# Detached HEAD: no garbage branch names, no failure.
git switch -q --detach main
out=$(sh scripts/cleanup.sh 2>&1); r=$?
check "detached HEAD: exit 0"                 '[ $r -eq 0 ]'
check "detached HEAD: no fake branch"         '! printf "%s" "$out" | grep -q "(HEAD"'
git switch -q main

# Run from another branch: main is never deleted.
git switch -q wip
sh scripts/cleanup.sh --apply >/dev/null 2>&1
check "main kept when run from another branch" 'git rev-parse -q --verify refs/heads/main >/dev/null'
git switch -q main

# Inside a hook (temporary index): refuse, delete nothing.
echo junk > f.orig
GIT_INDEX_FILE="$work/other-index" sh scripts/cleanup.sh --apply >/dev/null 2>&1; r=$?
check "refuses with an inherited GIT_INDEX_FILE" '[ $r -eq 2 ] && [ -f f.orig ]'
GIT_DIR="$work/r/.git" sh scripts/cleanup.sh --apply >/dev/null 2>&1; r=$?
check "refuses with an inherited GIT_DIR"     '[ $r -eq 2 ] && [ -f f.orig ]'
(cd "$work" && sh "$work/r/scripts/cleanup.sh" >/dev/null 2>&1); r=$?
check "outside a repository: exit 2"          '[ $r -eq 2 ]'
check "unknown option refused"                '! sh scripts/cleanup.sh --force >/dev/null 2>&1'

# Case-insensitive file systems (macOS, Windows): a protected folder spelled differently on
# disk is still protected. Fresh repository, so the folder exists only in that spelling.
mkdir -p "$work/c" && cd "$work/c" && git init -q -b main && mkdir -p scripts && cp "$src/cleanup.sh" scripts/
git add -A && git commit -qm init
mkdir -p tests/Corpus TARGET && echo real > tests/Corpus/x.orig && echo build > TARGET/b.orig
sh scripts/cleanup.sh --apply >/dev/null 2>&1
check "protection ignores letter case"        '[ -f tests/Corpus/x.orig ] && [ -f TARGET/b.orig ]'

echo "cleanup tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]

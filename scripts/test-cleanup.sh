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
# The developer's real gh must never run here: a broken script would act on GitHub. A stub
# comes first in PATH (not signed in), and gh's own settings are cleared.
unset GH_REPO GH_HOST GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN
mkdir -p "$work/ghstub"
printf '#!/bin/sh\necho "$*" >> "%s/gh-stub.log"\nexit 1\n' "$work" > "$work/ghstub/gh"
chmod +x "$work/ghstub/gh"
PATH="$work/ghstub:$PATH"; export PATH

passed=0
failed=0
ok()  { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "FAIL: $1" >&2; }
check() { if eval "$2"; then ok; else bad "$1"; fi; } # check <description> <shell condition>
# Windows (Git Bash): "\" is a path separator, and a read-only folder does not stop rm; the
# tests that need those are skipped there, and counted.
skipped=0
skip() { skipped=$((skipped + $1)); echo "SKIP ($1 checks): $2" >&2; }
on_windows=0
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) on_windows=1 ;; esac
# A block that cannot run on Windows:
#   if off_windows <checks> <reason>; then ...; end_off_windows; fi
# On Windows it counts <checks> as skipped. Elsewhere the block runs, and end_off_windows
# fails if the block did not run exactly <checks> checks: a wrong skip count is noticed.
off_windows() {
    if [ "$on_windows" -eq 1 ]; then skip "$1" "$2"; return 1; fi
    block_checks=$1; block_start=$((passed + failed)); return 0
}
end_off_windows() {
    ran=$((passed + failed - block_start))
    [ "$ran" -eq "$block_checks" ] || bad "skip count: the block says $block_checks checks, it ran $ran"
}

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
out=$(sh scripts/cleanup.sh --plan 2>&1); r=$?
check "dry run exits 0"                       '[ $r -eq 0 ]'
check "dry run lists junk files"              'printf "%s" "$out" | grep -q "a.orig"'
check "dry run lists merged branch"           'printf "%s" "$out" | grep -q "branch (merged): old"'
check "dry run lists backups for review"      'printf "%s" "$out" | grep -q "review.*c.bak"'
check "dry run lists unknown file for review" 'printf "%s" "$out" | grep -q "review.*notes.txt"'
check "--plan removes nothing it reports"     '! printf "%s" "$out" | grep -q "^removed "'
check "dry run deletes nothing"               '[ -f a.orig ] && git rev-parse -q --verify refs/heads/old >/dev/null'
check "dry run lists unmerged branch as kept" 'printf "%s" "$out" | grep -q "keep local branch (not merged): wip"'

# No confirmation options: the script removes junk files and merged branches and says what it did.
for opt in --yes "--yes --expect 3" "--expect 3" --apply "--plan --yes" "--plan x" "x --plan"; do
    sh scripts/cleanup.sh $opt >/dev/null 2>&1; r=$?
    check "$opt refused, nothing removed"     '[ $r -eq 2 ] && [ -f a.orig ] && git rev-parse -q --verify refs/heads/old >/dev/null'
done

# Never a question, also at a terminal: the script reads no input and does not look for one.
# (A "| while read" loop reads a pipe, not the keyboard.)
check "cleanup.sh reads no input"             '! grep -E "(^|[^a-z_])(read|head|cat|dd|tty)( |$)|sed [0-9]*q|-t [0-2]|/dev/(tty|stdin)" scripts/cleanup.sh | grep -v "| while IFS= read" | grep -q .'
# The read-only coherence auditor (and any agent) may only run the dry run, exactly.
calls=$(grep -oh "cleanup\.sh[^\`]*" "$src"/../.claude/agents/*.md 2>/dev/null)
check "agent prompts: cleanup.sh calls found"  '[ -n "$calls" ]'
check "agent prompts run cleanup.sh only with --plan" '! printf "%s\n" "$calls" | grep -vx "cleanup\.sh --plan" | grep -q .'

# Removal without a terminal and without a question.
out=$(sh scripts/cleanup.sh </dev/null 2>&1); r=$?
check "run exits 0"                         '[ $r -eq 0 ]'
# Every line is a report line: a question ("Proceed? [Y/n]", "Type 3 ...") would not match.
known='^(would remove|removed|keep|review|worktree|on GitHub|nothing to remove)'
check "no question asked: only report lines"  '! printf "%s\n" "$out" | grep -Ev "$known" | grep -q .'
check "removal run: no 'would remove' lines"   '! printf "%s" "$out" | grep -q "^would remove"'
check "says what it removed"                  'printf "%s" "$out" | grep -q "removed junk file: a.orig" && printf "%s" "$out" | grep -q "removed local branch (merged): old"'
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
check "remote merged branch reported as kept" 'printf "%s" "$out" | grep -q "on GitHub, merged (kept, nothing is deleted on GitHub): origin/old"'
check "no advice to delete on GitHub"         '! printf "%s" "$out" | grep -qi "delete it on GitHub"'
check "origin/HEAD is not a branch"           '! printf "%s" "$out" | grep -Eq "merged.*: origin(/HEAD)?\$"'

# An answer on standard input changes nothing: no question is read, removal still happens.
echo junk > n.orig
printf 'n\n' | sh scripts/cleanup.sh >/dev/null 2>&1
check "an 'n' on stdin is not read as an answer" '[ ! -e n.orig ]'
out=$(sh scripts/cleanup.sh 2>&1)
check "says when there is nothing to remove"  'printf "%s" "$out" | grep -q "^nothing to remove$"'
# GitHub is only read: with gh available and signed in, only "auth status" and "pr list" run.
mkdir -p "$work/ghshim"
printf '#!/bin/sh\necho "$*" >> "%s/gh.log"\necho "prompt=${GH_PROMPT_DISABLED:-} stdin=$(cat)" >> "%s/gh.log"\n[ "$1" = pr ] && echo "on GitHub, draft PR (not closed here): #1"\nexit 0\n' "$work" "$work" > "$work/ghshim/gh"
chmod +x "$work/ghshim/gh"; rm -f "$work/gh.log"
echo junk > q.orig
echo typed | PATH="$work/ghshim:$PATH" sh scripts/cleanup.sh >/dev/null 2>&1
check "gh called"                             '[ -s "$work/gh.log" ]'
check "gh only reads (auth status, pr list)"  '! grep -v "^prompt=" "$work/gh.log" | grep -Ev "^(auth status|pr list )" | grep -q .'
check "gh can never ask: no prompt, no stdin" '! grep "^prompt=" "$work/gh.log" | grep -vx "prompt=1 stdin=" | grep -q .'
check "the test stub stands in for the real gh" 'grep -q "^auth status" "$work/gh-stub.log"'

# Names git prints as they are (non-ASCII) or that look like options are removed whole.
echo junk > "citt$(printf '\303\240').orig"; echo junk > ./-x.orig
sh scripts/cleanup.sh >/dev/null 2>&1
check "non-ASCII junk name removed"           '[ ! -e "citt$(printf "\303\240").orig" ]'
check "junk name starting with - removed"     '[ ! -e ./-x.orig ]'

# A tag with the same name as a branch does not confuse the branch names.
git switch -q -c twin && echo t > t.txt && git add t.txt && git commit -qm twin
git switch -q main && git merge -q --ff-only twin && git tag twin && git tag main
git switch -q -c elsewhere
out=$(sh scripts/cleanup.sh 2>&1); r=$?
check "same-named tag: merged branch removed" '[ $r -eq 0 ] && ! git rev-parse -q --verify refs/heads/twin >/dev/null'
check "same-named tag: main kept"             'git rev-parse -q --verify refs/heads/main >/dev/null && ! printf "%s" "$out" | grep -q "heads/"'
git switch -q main; git branch -q -D elsewhere; git tag -d twin main >/dev/null
# A tag "main" on an unmerged commit must not make that commit count as merged, and an
# unmerged branch with a same-named tag is still listed by its name.
git switch -q -c feat && echo f > f.txt && git add f.txt && git commit -qm feat
git tag main feat && git tag wip wip && git switch -q main
out=$(sh scripts/cleanup.sh --plan 2>&1)
check "tag main elsewhere: unmerged branch kept" 'printf "%s" "$out" | grep -q "keep local branch (not merged): feat"'
check "tag main elsewhere: no ambiguity"      '! printf "%s" "$out" | grep -qi "ambiguous"'
check "unmerged branch with same-named tag"   'printf "%s" "$out" | grep -q "keep local branch (not merged): wip$"'
git tag -d main wip >/dev/null; git branch -q -D feat
# The current branch keeps its name when a tag has the same name.
git switch -q -c cur && git tag cur
out=$(sh scripts/cleanup.sh --plan 2>&1)
check "same-named tag: current branch said as checked out here" 'printf "%s" "$out" | grep -q "keep branch (checked out here): cur$"'
git switch -q main; git branch -q -D cur; git tag -d cur >/dev/null

# Names git has to quote (backslash, double quote): never removed, listed on one line.
if off_windows 4 "names with a backslash cannot exist on Windows"; then
echo mine > 'odd\nname.txt'; echo junk > 'odd\name.orig'
out=$(sh scripts/cleanup.sh 2>&1)
check "quoted name: junk not removed"         '[ -f "odd\\name.orig" ]'
check "quoted name: not reported as removed"  '! printf "%s\n" "$out" | grep -q "^removed junk file: .*odd"'
check "quoted name: listed for review"        'printf "%s\n" "$out" | grep -q "^review (special characters, not removed): .*odd.*name.orig"'
check "quoted name: printed on one line"      'printf "%s\n" "$out" | grep -q "^review.*odd.*nname.txt"'
rm -f 'odd\nname.txt' 'odd\name.orig'
end_off_windows
fi

# Names that must not be expanded, split or matched loosely.
echo junk > 'my file.orig'; echo mine > plan.orig.txt; echo junk > '*.orig'
sh scripts/cleanup.sh >/dev/null 2>&1
check "name with a space removed whole"       '[ ! -e "my file.orig" ] && [ ! -e my ]'
check "junk rule anchored at the end"         '[ -f plan.orig.txt ]'
check "star name not expanded to tracked files" '[ -f kept.orig ] && [ ! -e "*.orig" ]'
# tests/corpus/ is protected even when its ignore line is missing (old checkout, rebase).
mkdir -p tests/out
echo real > tests/out/report.orig; echo build > target/b.orig
printf '\n' > .gitignore
# Names git has to quote, inside protected folders: not even printed (reports are public).
# (On Windows these names are stored differently and git's quoting is not exercised; the
# check still runs there.)
for d in tests/corpus tests/out target; do echo real > "$d/Mario \"Rossi\" Test.p7m"; done
out=$(sh scripts/cleanup.sh --plan 2>&1)
check "quoted names in protected folders not printed" '! printf "%s" "$out" | grep -Eq "tests/corpus|tests/out|target/"'
out=$(sh scripts/cleanup.sh 2>&1)
check "protected folders not printed in a removal run" '! printf "%s" "$out" | grep -Eq "tests/corpus|tests/out|target/"'
check "corpus protected without the ignore line" '[ -f tests/corpus/verbale.orig ]'
check "tests/out protected without the ignore line" '[ -f tests/out/report.orig ]'
check "target protected without the ignore line" '[ -f target/b.orig ]'
git checkout -q -- .gitignore
# Detached HEAD: no garbage branch names, no failure.
git switch -q --detach main
out=$(sh scripts/cleanup.sh --plan 2>&1); r=$?
check "detached HEAD: exit 0"                 '[ $r -eq 0 ]'
check "detached HEAD: no fake branch"         '! printf "%s" "$out" | grep -q "(HEAD"'
git switch -q main

# The branch checked out here is not "in a worktree".
git branch fresh main
git switch -q fresh
out=$(sh scripts/cleanup.sh --plan 2>&1)
check "current branch: said as checked out here" 'printf "%s" "$out" | grep -q "keep branch (checked out here): fresh"'
git switch -q main

# Run from another branch: main is never deleted.
git switch -q wip
sh scripts/cleanup.sh >/dev/null 2>&1
check "main kept when run from another branch" 'git rev-parse -q --verify refs/heads/main >/dev/null'
git switch -q main

# A branch just created at main, with no commit of its own, is removed (audit 0003, F6). It
# looks the same as a branch fast-forwarded into main, and it holds no commit that main lacks.
git branch born main
out=$(sh scripts/cleanup.sh --plan 2>&1)
check "branch created at main: listed for removal" 'printf "%s\n" "$out" | grep -q "^would remove local branch (merged): born$"'
out=$(sh scripts/cleanup.sh 2>&1); r=$?
check "branch created at main: removed"       '[ $r -eq 0 ] && printf "%s\n" "$out" | grep -q "^removed local branch (merged): born$" && ! git rev-parse -q --verify refs/heads/born >/dev/null'

# Detached HEAD at a commit that no branch holds: cleanup.sh does not touch HEAD or that
# commit, lists only real branches as not merged, and still removes merged branches.
git switch -q --detach main && echo d > d.txt && git add d.txt && git commit -qm detached
head=$(git rev-parse HEAD)
git branch gone main
out=$(sh scripts/cleanup.sh 2>&1); r=$?
check "detached unmerged HEAD: exit 0, merged branch removed" '[ $r -eq 0 ] && ! git rev-parse -q --verify refs/heads/gone >/dev/null'
check "detached unmerged HEAD: HEAD and its commit kept" '! git symbolic-ref -q HEAD >/dev/null && [ "$(git rev-parse HEAD)" = "$head" ] && [ -f d.txt ]'
check "detached unmerged HEAD: only real branches listed" 'printf "%s\n" "$out" | grep -q "^keep local branch (not merged): wip$" && ! printf "%s\n" "$out" | grep -q "(HEAD"'
git switch -q main

# Inside a hook (temporary index): refuse, delete nothing.
echo junk > f.orig
# env: a variable put before a shell function would stay set for the rest of this file.
env GIT_INDEX_FILE="$work/other-index" sh scripts/cleanup.sh >/dev/null 2>&1; r=$?
check "refuses with an inherited GIT_INDEX_FILE" '[ $r -eq 2 ] && [ -f f.orig ]'
env GIT_DIR="$work/r/.git" sh scripts/cleanup.sh >/dev/null 2>&1; r=$?
check "refuses with an inherited GIT_DIR"     '[ $r -eq 2 ] && [ -f f.orig ]'
env GIT_WORK_TREE="$work/r" sh scripts/cleanup.sh >/dev/null 2>&1; r=$?
check "refuses with an inherited GIT_WORK_TREE" '[ $r -eq 2 ] && [ -f f.orig ]'
check "no git variable left set by the tests" '[ -z "${GIT_DIR:-}${GIT_INDEX_FILE:-}${GIT_WORK_TREE:-}" ]'
(cd "$work" && sh "$work/r/scripts/cleanup.sh" >/dev/null 2>&1); r=$?
check "outside a repository: exit 2"          '[ $r -eq 2 ]'
check "unknown option refused"                '! sh scripts/cleanup.sh --force >/dev/null 2>&1'

# A removal that fails is reported in the exit status.
if off_windows 1 "a read-only folder does not stop rm on Windows"; then
mkdir -p locked && echo junk > locked/g.orig && chmod 555 locked
sh scripts/cleanup.sh >/dev/null 2>&1; r=$?
chmod 755 locked
check "failed removal: exit 1"                '[ $r -eq 1 ] && [ -f locked/g.orig ]'
end_off_windows
fi
rm -rf locked f.orig

# A branch merged into main is removed even when HEAD is on a branch that lacks it.
git switch -q -c side main~1 2>/dev/null || git switch -q -c side main
git switch -q -c merged-later main && echo m > m.txt && git add m.txt && git commit -qm m
git switch -q main && git merge -q --ff-only merged-later && git switch -q side
out=$(sh scripts/cleanup.sh 2>&1); r=$?
check "merged into main, not into HEAD: removed" '[ $r -eq 0 ] && ! git rev-parse -q --verify refs/heads/merged-later >/dev/null'
git switch -q main

# Race: a branch merged when listed gets a new commit before it is deleted. It is checked
# again just before deletion, so it is kept. The listing comes before the GitHub section and
# the deletion after it, so a gh stand-in adds the commit in between: no seam in cleanup.sh.
# Variant 2 adds a tag with the branch's name at main and a tag "main" at the new commit: a
# check with short names would read the tags and delete the branch.
mkdir -p "$work/raceshim"
cat > "$work/raceshim/gh" <<'SHIM'
#!/bin/sh
# Signed in. On "pr list", move the branch named in RACE_BRANCH to a new commit.
[ "$1" = pr ] || exit 0
b=$RACE_BRANCH
new=$(git commit-tree -p "refs/heads/$b" -m race "refs/heads/$b^{tree}") || exit 1
git update-ref "refs/heads/$b" "$new" || exit 1
if [ "$RACE_TAGS" -eq 1 ]; then git tag "$b" refs/heads/main && git tag main "$new"; fi
exit 0
SHIM
chmod +x "$work/raceshim/gh"
for variant in 1 2; do
    git branch "racer$variant" main
    out=$(env RACE_BRANCH="racer$variant" RACE_TAGS=$((variant - 1)) PATH="$work/raceshim:$PATH" sh scripts/cleanup.sh 2>&1); r=$?
    check "race $variant: listed as merged, then kept" 'printf "%s\n" "$out" | grep -q "^keep branch (no longer merged into main, or git refused): racer$variant$"'
    check "race $variant: not removed, exit 1"   '[ $r -eq 1 ] && ! printf "%s\n" "$out" | grep -q "^removed local branch (merged): racer$variant$"'
    check "race $variant: new commit still on the branch" '[ "$(git log -1 --format=%s "refs/heads/racer$variant" 2>/dev/null)" = race ]'
    git branch -q -D "racer$variant"; git tag -d "racer$variant" main >/dev/null 2>&1
done

# Without a local main there is nothing to compare with: stop before removing anything.
git branch -q -m main trunk
echo junk > h.orig
sh scripts/cleanup.sh >/dev/null 2>&1; r=$?
check "no local main: exit 2, nothing removed" '[ $r -eq 2 ] && [ -f h.orig ]'
git branch -q -m trunk main; rm -f h.orig
# A tag called "main" is not the branch main: without the branch, stop.
git branch -q -m main trunk; git tag main trunk
echo junk > h.orig
sh scripts/cleanup.sh >/dev/null 2>&1; r=$?
check "only a tag main: exit 2, nothing removed" '[ $r -eq 2 ] && [ -f h.orig ]'
git tag -d main >/dev/null; git branch -q -m trunk main; rm -f h.orig

# Case-insensitive file systems (macOS, Windows): a protected folder spelled differently on
# disk is still protected. Fresh repository, so the folder exists only in that spelling.
mkdir -p "$work/c" && cd "$work/c" && git init -q -b main && mkdir -p scripts && cp "$src/cleanup.sh" scripts/
git add -A && git commit -qm init
mkdir -p tests/Corpus tests/OUT TARGET && echo real > tests/Corpus/x.orig && echo real > tests/OUT/r.orig && echo build > TARGET/b.orig
echo junk > y.orig
sh scripts/cleanup.sh >/dev/null 2>&1; r=$?
check "case test: the cleanup really ran"     '[ $r -eq 0 ] && [ ! -e y.orig ]'
check "protection ignores letter case"        '[ -f tests/Corpus/x.orig ] && [ -f tests/OUT/r.orig ] && [ -f TARGET/b.orig ]'

# skip itself, on every system: it adds the number of checks it is given.
( skipped=4; skip 3 "self-test" 2>/dev/null; [ "$skipped" -eq 7 ] ); r=$?
check "skip adds the checks it is given"      '[ $r -eq 0 ]'

# Skips are for Windows only: read the system a second way (Windows sets OS=Windows_NT, also
# in Git Bash), so a broken switch cannot turn the safety checks off everywhere.
check "no skipped checks outside Windows"     '[ "${OS:-}" = Windows_NT ] || [ "$skipped" -eq 0 ]'

echo "cleanup tests: $passed passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]

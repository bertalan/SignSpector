#!/bin/sh
# Tests for scripts/check-public.sh and scripts/audit-status.sh, run in throw-away git
# repositories. Used by CI (rules job) and runnable by hand: sh scripts/test-scripts.sh
# Test identities and paths below are fake on purpose. Sensitive-looking data is written with
# octal escapes (\143 = c, \125 = U, \113 = K, \141 = a, \115 = M, \104 = D, \100 = @) so that this file does not match the
# patterns it tests; printf turns them into the real characters at run time.
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
expect() { # expect <description> <expected exit> <actual exit>
    if [ "$2" -eq "$3" ]; then passed=$((passed + 1)); else
        failed=$((failed + 1)); echo "FAIL: $1 (expected exit $2, got $3)" >&2; fi
}

new_repo() {
    rm -rf "$work/r" && mkdir -p "$work/r/scripts" && cd "$work/r" || exit 2
    git init -q -b main
    cp "$src/check-public.sh" "$src/audit-status.sh" scripts/
    git add scripts && git commit -qm initial
}

# Stages one file with the given content (printf format) and runs the staged check.
staged() { # staged <description> <expected exit> <path> <printf content>
    mkdir -p "$(dirname "$3")"
    printf "$4" > "$3"
    git add -f -- "$3"
    sh scripts/check-public.sh --staged 2>/dev/null; expect "$1" "$2" $?
    git rm -q --cached -- "$3"; rm -f -- "$3"
}

# --- check-public.sh -----------------------------------------------------------------------
new_repo
staged "clean source file"            0 src/lib.rs 'pub fn f() {}\n'
staged "example email allowed"        0 docs/note.md 'write to user@example.com\n'
staged "real email"                   1 docs/note.md 'write to mario.rossi@gmail.\143om\n'
staged "local path with user name"    1 src/x.rs '// /\125sers/mrossi/Desktop\n'
staged "windows user path"            1 src/x.rs '// C:\\\\\125sers\\\\mrossi\\\\x\n'
staged "windows path, one backslash"  1 docs/note.md 'see C:\\\125sers\\mrossi\n'
staged "windows path, forward slash"  1 docs/note.md 'see C:/\125sers/mrossi\n'
staged "codice fiscale in binary"     1 tests/fixtures/a.p7m '\060\202TINIT-RSSMRA80A01H501\125\000\377'
staged "private key"                  1 tests/fixtures/k.pem 'x\n-----BEGIN PRIVATE \113EY-----\n'
staged "github token"                 1 .github/workflows/x.yml 'token: ghp_\141bcdefghijklmnopqrstuvwxyz12\n'
staged "pdf not allowed"              1 docs/Relazione.pdf '%%PDF-1.7\n'
staged "p7m outside fixtures"         1 'docs/Relazione citt\303\240.pdf.p7m' 'x'
staged "real corpus path"             1 tests/corpus/x.rs 'fn x() {}\n'
staged "glob character in name"       1 'docs/a*.md' 'x\n'

sh scripts/check-public.sh --tree nosuchrev 2>/dev/null; expect "bad revision" 2 $?
sh scripts/check-public.sh --tree HEAD 2>/dev/null;      expect "clean commit" 0 $?
git commit -q --allow-empty -m "$(printf 'contact: mario.rossi@gmail.\143om')"
sh scripts/check-public.sh --tree HEAD 2>/dev/null;      expect "email in commit message" 1 $?
printf 'Fix\n\nCo-Authored-By: Bot <noreply@example.com>\n' > "$work/msg"
sh scripts/check-public.sh --message "$work/msg" 2>/dev/null; expect "noreply in message" 0 $?
printf 'Fix /\125sers/mrossi/x\n' > "$work/msg"
sh scripts/check-public.sh --message "$work/msg" 2>/dev/null; expect "path in message" 1 $?
sh scripts/check-public.sh --bogus 2>/dev/null;          expect "unknown mode" 2 $?

# --- audit-status.sh -----------------------------------------------------------------------
commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }
audit()  { mkdir -p docs/audits; echo audit > "docs/audits/$1.md"; git add docs; git commit -qm "audit: $1"; }
gate_commit() { echo x >> staged.txt; git add staged.txt; sh scripts/audit-status.sh --gate-commit 2>/dev/null; r=$?; git reset -q; rm -f staged.txt; return $r; }

new_repo
commit a; commit b
gate_commit;                                          expect "2 commits: commit allowed" 0 $?
commit c
gate_commit;                                          expect "3 commits: 4th refused" 1 $?
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "3 commits: push allowed" 0 $?
commit d
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "4 commits: push refused" 1 $?
audit 0001
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "after audit: push allowed" 0 $?
gate_commit;                                          expect "after audit: commit allowed" 0 $?

# An audit mixed with code does not reset the counter.
commit e; commit f; commit g
mkdir -p docs/audits; echo audit > docs/audits/0002.md; echo code > h.txt
git add docs h.txt; git commit -qm "audit mixed with code"
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "mixed audit does not count" 1 $?

# A branch that starts with an audit and then adds many commits is measured on its own tip,
# not on a merge commit (CI on pull requests).
new_repo
git switch -q -c feature
audit 0001
for i in 1 2 3 4 5 6 7 8; do commit "f$i"; done
tip=$(git rev-parse HEAD)
git switch -q main
git merge -q --no-ff --no-edit feature
sh scripts/audit-status.sh --gate-push "$tip" 2>/dev/null; expect "branch tip past cadence" 1 $?
sh scripts/audit-status.sh --gate-push nosuchrev 2>/dev/null; expect "gate: bad revision" 2 $?

# --- review findings (written before the fixes) ----------------------------------------------
new_repo
# B3: codice fiscale inside DER, followed by the next tag byte (0x31 SET, 0x30 SEQUENCE).
staged "cf followed by SET tag"       1 tests/fixtures/a.p7m '\023\020RSSMRA80A01H501\125\061\013'
staged "cf followed by SEQUENCE tag"  1 tests/fixtures/a.p7m '\023\020RSSMRA80A01H501\125\060\202'
staged "cf preceded by a letter"      1 tests/fixtures/a.p7m 'xRSSMRA80A01H501\125\000'
staged "cf between underscores"       1 docs/note.md 'file_RSSMRA80A01H501\125_firmato\n'
# B10: look-alike addresses, data in paths, keys in fixtures, comment lines in messages.
staged "noreply inside a real address" 1 docs/note.md 'mario.noreply@gmail.\143om\n'
staged "example.com as a prefix"      1 docs/note.md 'mario\100example.com.realcompany.\151t\n'
staged "email in a file name"         1 "$(printf 'mario.rossi@gmail.\143om.md')" 'x\n'
staged "home with capital letter"     1 docs/note.md '/home/\115ario/x\n'
staged "documents and settings"       1 docs/note.md 'C:\\\104ocuments and Settings\\mrossi\n'
staged "p12 in fixtures"              1 tests/fixtures/signer.p12 '\060\202\001'
staged "key in fixtures"              1 tests/fixtures/signer.key 'x\n'
staged "pem in fixtures"              1 tests/fixtures/ca.pem 'x\n'
printf '# /\125sers/mrossi/x\nFix\n' > "$work/msg"
sh scripts/check-public.sh --message "$work/msg" 2>/dev/null; expect "path in a # line of the message" 1 $?
# B4: author and committer identity are published too.
GIT_AUTHOR_EMAIL=$(printf 'mario.rossi@gmail.\143om') git commit -q --allow-empty -m clean
sh scripts/check-public.sh --tree HEAD 2>/dev/null;      expect "real author email" 1 $?
new_repo
GIT_COMMITTER_EMAIL=$(printf 'mario.rossi@gmail.\143om') git commit -q --allow-empty -m clean
sh scripts/check-public.sh --tree HEAD 2>/dev/null;      expect "real committer email" 1 $?
new_repo
GIT_AUTHOR_EMAIL=1+user@users.noreply.github.com git commit -q --allow-empty -m clean
sh scripts/check-public.sh --tree HEAD 2>/dev/null;      expect "github noreply author" 0 $?

# B5: what counts as an audit.
new_repo
git switch -q -c feature
for i in 1 2 3 4 5 6; do commit "f$i"; done
mkdir -p docs/audits; echo audit > docs/audits/0001.md; echo code > g.txt
git add docs g.txt; git commit -qm "audit mixed with code"
git switch -q main
git merge -q --no-ff --no-edit feature
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "merge commit is not an audit" 1 $?
new_repo
audit 0001
commit a; commit b; commit c
git rm -q docs/audits/0001.md; git commit -qm "remove report"
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "deleting a report is not an audit" 1 $?

# Leftovers of the work itself must not be committed (PR texts, notes, review dumps).
new_repo
staged "PR description file"          1 PR_BODY.md 'x\n'
staged "notes at the root"            1 NOTES.md 'x\n'
staged "review dump in docs"          1 docs/review-output.txt 'x\n'
staged "README allowed"               0 README.md 'x\n'
staged "CHANGELOG allowed"            0 CHANGELOG.md 'x\n'

# Data in a file name the allowlist accepts (fixtures allow any plain name).
new_repo
staged "codice fiscale in a fixture name" 1 "$(printf 'tests/fixtures/RSSMRA80A01H501\125.p7m')" 'x'
# Commits brought in by a merge after an audit still count.
new_repo
audit 0001
git switch -q -c feature
commit m1; commit m2; commit m3; commit m4
git switch -q main
git merge -q --no-ff --no-edit feature
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "merged commits after an audit count" 1 $?

# A report added inside a merge commit itself is not an audit (git shows no diff for merges).
new_repo
git switch -q -c feature
commit e1; commit e2; commit e3; commit e4
git switch -q main
git merge -q --no-ff --no-commit feature >/dev/null 2>&1
mkdir -p docs/audits; echo audit > docs/audits/0001.md; git add docs
git commit -qm "merge with a report inside"
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "report inside a merge is not an audit" 1 $?

# B9/B11: commit ranges, in one tested place (pre-push and CI call it).
new_repo
git init -q --bare "$work/remote.git"; git remote add origin "$work/remote.git"
git push -q origin main 2>/dev/null
git switch -q -c topic
printf 'mario.rossi@gmail.\143om\n' > leak.md; git add leak.md; git commit -qm "add"
git rm -q leak.md; git commit -qm "remove"
sh scripts/check-public.sh --range "$(git rev-parse main)" HEAD 2>/dev/null; expect "range: leak added then removed" 1 $?
sh scripts/check-public.sh --range remotes HEAD 2>/dev/null;  expect "range: new branch, not on remote" 1 $?
sh scripts/check-public.sh --range remotes main 2>/dev/null;  expect "range: nothing new" 0 $?
sh scripts/check-public.sh --range nosuchrev HEAD 2>/dev/null; expect "range: bad base" 2 $?
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;      expect "range: tip only (leak removed)" 0 $?

echo "scripts tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]

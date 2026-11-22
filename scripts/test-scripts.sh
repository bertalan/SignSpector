#!/bin/sh
# Tests for scripts/check-public.sh and scripts/audit-status.sh, run in throw-away git
# repositories. Used by CI (rules job) and runnable by hand: sh scripts/test-scripts.sh
# Test identities and paths below are fake on purpose. Sensitive-looking data is written with
# octal escapes (\143 = c, \125 = U, \113 = K, \141 = a) so that this file does not match the
# patterns it tests; printf turns them into the real characters at run time.
set -u
export LC_ALL=C

src=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
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

echo "scripts tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]

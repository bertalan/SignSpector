#!/bin/sh
# Tests for scripts/check-public.sh and scripts/audit-status.sh, run in throw-away git
# repositories. Run by the pre-commit hook when scripts or hooks change, by CI on all three
# systems, and by hand: sh scripts/test-scripts.sh
# Test identities and paths below are fake on purpose. Sensitive-looking data is written with
# octal escapes (\143 = c, \125 = U, \113 = K, \141 = a, \115 = M, \104 = D, \100 = @) so that this file does not match the
# patterns it tests; printf turns them into the real characters at run time.
set -u
# No LC_ALL here: the scripts must set their own locale (hooks run in the user's locale).

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

# expect_reason <description> <reason in stderr> <command...>: exit 1 for that reason only.
expect_reason() {
    desc=$1; reason=$2; shift 2
    err=$("$@" 2>&1 >/dev/null); r=$?
    if [ "$r" -eq 1 ] && printf '%s\n' "$err" | grep -q "$reason"; then passed=$((passed + 1)); else
        failed=$((failed + 1)); echo "FAIL: $desc (exit $r, expected 1 with \"$reason\"; got: $err)" >&2; fi
}

# report_section <heading start> <report>: the non-blank lines of the first report section whose
# heading starts with "== <heading start>", without the heading.
report_section() {
    printf '%s\n' "$2" | awk -v h="== $1" '
        on && /^== / { exit }
        on && NF { print }
        index($0, h) == 1 { on = 1 }'
}

# expect_absent <description> <heading start> <extended regex> <report>: the section has at
# least one line, and no line matches. A section that prints nothing is a failure, never a pass.
expect_absent() {
    lines=$(report_section "$2" "$4")
    if [ -n "$lines" ] && ! printf '%s\n' "$lines" | grep -Eq -- "$3"; then passed=$((passed + 1)); else
        failed=$((failed + 1)); echo "FAIL: $1 (section \"$2\" is empty or has \"$3\")" >&2; fi
}

# Report-mode tests never call the real gh (network, user account): default gh says "not logged in".
unset GH_REPO GH_HOST GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN
mkdir -p "$work/nogh"; printf '#!/bin/sh\necho "$*" >> "%s/gh-stub.log"\nexit 1\n' "$work" > "$work/nogh/gh"; chmod +x "$work/nogh/gh"
# The same for rustup: the report's "Rust" section must not reach the network in the tests.
printf '#!/bin/sh\necho "$*" >> "%s/rustup-stub.log"\nexit 1\n' "$work" > "$work/nogh/rustup"; chmod +x "$work/nogh/rustup"
PATH="$work/nogh:$PATH"

new_repo() {
    rm -rf "$work/r" && mkdir -p "$work/r/scripts" && cd "$work/r" || exit 2
    git init -q -b main
    cp "$src/check-public.sh" "$src/audit-status.sh" "$src/cleanup.sh" scripts/
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
mkdir -p docs; echo clean > docs/a.md; git add docs; git commit -qm a
printf 'mario.rossi@gmail.\143om\n' > 'docs/[ab].md'; git add -f -- 'docs/[ab].md'
expect_reason "bracket name is not expanded to another file" "docs/\[ab\].md: path not allowed" sh scripts/check-public.sh --staged
git rm -q --cached -- 'docs/[ab].md'; rm -f -- 'docs/[ab].md'

sh scripts/check-public.sh --range tip nosuchrev 2>/dev/null; expect "bad revision" 2 $?
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;      expect "clean commit" 0 $?
git commit -q --allow-empty -m "$(printf 'contact: mario.rossi@gmail.\143om')"
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;      expect "email in commit message" 1 $?
printf 'Fix\n\nCo-Authored-By: Bot <noreply@example.com>\n' > "$work/msg"
sh scripts/check-public.sh --message "$work/msg" 2>/dev/null; expect "noreply in message" 0 $?
printf 'Fix /\125sers/mrossi/x\n' > "$work/msg"
sh scripts/check-public.sh --message "$work/msg" 2>/dev/null; expect "path in message" 1 $?
sh scripts/check-public.sh --bogus 2>/dev/null;          expect "unknown mode" 2 $?

# --- audit-status.sh -----------------------------------------------------------------------
commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }
audit()  { mkdir -p docs/audits; echo audit > "docs/audits/$1.md"; git add docs; git commit -qm "audit: $1"; }
gate_commit() { echo x >> staged.txt; git add staged.txt; sh scripts/audit-status.sh --gate-commit 2>/dev/null; r=$?; git reset -q; rm -f staged.txt; return $r; }

gate_audit() { mkdir -p docs/audits; echo a > docs/audits/9999.md; git add docs; sh scripts/audit-status.sh --gate-commit 2>/dev/null; r=$?; git reset -q; rm -f docs/audits/9999.md; return $r; }

new_repo
commit a; commit b; commit c; commit d
gate_commit;                                          expect "4 commits: commit allowed" 0 $?
commit e
gate_commit;                                          expect "5 commits: 6th refused" 1 $?
gate_audit;                                           expect "5 commits: the audit commit itself allowed" 0 $?
sh scripts/audit-status.sh --gate-commit 2>/dev/null; expect "5 commits: nothing staged is not an audit" 1 $?
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "5 commits: push allowed" 0 $?
commit f
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "6 commits: push refused" 1 $?
audit 0001
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "after audit: push allowed" 0 $?
gate_commit;                                          expect "after audit: commit allowed" 0 $?
commit g; commit h; commit i; commit j; commit k
git rm -q docs/audits/0001.md
sh scripts/audit-status.sh --gate-commit 2>/dev/null; expect "staged deletion of a report is not an audit" 1 $?
git reset -q; git checkout -q -- docs/audits/0001.md
echo changed >> docs/audits/0001.md; git add docs; git commit -qm "edit report"
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "editing a report is not an audit" 1 $?

# An audit mixed with code does not reset the counter.
new_repo
audit 0001
commit e; commit f; commit g; commit g2; commit g3
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
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;      expect "real author email" 1 $?
new_repo
GIT_COMMITTER_EMAIL=$(printf 'mario.rossi@gmail.\143om') git commit -q --allow-empty -m clean
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;      expect "real committer email" 1 $?
new_repo
GIT_AUTHOR_EMAIL=1+user@users.noreply.github.com git commit -q --allow-empty -m clean
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;      expect "github noreply author" 0 $?

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
commit a; commit b; commit c; commit d; commit e
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
commit m1; commit m2; commit m3; commit m4; commit m5; commit m6
git switch -q main
git merge -q --no-ff --no-edit feature
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "merged commits after an audit count" 1 $?

# A report added inside a merge commit itself is not an audit (git shows no diff for merges).
new_repo
git switch -q -c feature
commit e1; commit e2; commit e3; commit e4; commit e5; commit e6
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
mkdir -p docs; printf 'mario.rossi@gmail.\143om\n' > docs/leak.md; git add docs; git commit -qm "add"
git rm -q docs/leak.md; git commit -qm "remove"
expect_reason "range: leak added then removed" "docs/leak.md: email address" sh scripts/check-public.sh --range "$(git rev-parse main)" HEAD
expect_reason "range: new branch, not on remote" "docs/leak.md: email address" sh scripts/check-public.sh --range remote:origin HEAD
sh scripts/check-public.sh --range remote:origin main 2>/dev/null;  expect "range: nothing new" 0 $?
sh scripts/check-public.sh --range nosuchrev HEAD 2>/dev/null; expect "range: bad base" 2 $?
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;      expect "range: tip only (leak removed)" 0 $?

# --- rules without a test until the second review --------------------------------------------
new_repo
mkdir -p docs; echo clean > docs/note.md
git add docs/note.md; git commit -qm note
printf 'mario.rossi@gmail.\143om\n' >> docs/note.md; git add docs/note.md
sh scripts/check-public.sh --staged 2>/dev/null;     expect "edit of an existing file scanned" 1 $?
git reset -q --hard
staged "envelope disguised as a doc"  1 docs/note.md.p7m 'x'
staged "README in a subfolder"        1 x/README.md 'x\n'
staged "source under the corpus"      1 tests/corpus/src/x.rs 'x\n'
staged "claude local settings"        1 .claude/settings.local.json '{}\n'
staged "agent prompt allowed"         0 .claude/agents/x.md 'x\n'
staged "script in a subfolder"        1 scripts/sub/x.sh 'x\n'
staged "hook backup"                  1 .githooks/pre-commit.bak 'x\n'
staged "other asset"                  1 assets/other.xml 'x\n'
staged "no trusted list in the repository" 1 assets/tsl-it.xml '<x/>\n'
staged "pfx in fixtures"              1 tests/fixtures/a.pfx 'x'
staged "private key in source"        1 src/x.rs '// -----BEGIN RSA PRIVATE \113EY-----\n'
staged "github fine-grained token"    1 src/x.rs '// github_\160at_11ABC\n'
staged "anthropic key"                1 src/x.rs '// sk-\141nt-api03-x\n'
staged "aws key"                      1 src/x.rs '// \101KIAABCDEFGHIJKLMNOP\n'
staged "slack token"                  1 src/x.rs '// xo\170b-123\n'

# Message body (not only the subject), and metadata of commits before the tip.
new_repo
git commit -q --allow-empty -m subject -m "$(printf 'body: mario.rossi@gmail.\143om')"
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;    expect "email in the message body" 1 $?
new_repo
base=$(git rev-parse HEAD)
git commit -q --allow-empty -m "$(printf 'see /\125sers/mrossi/x')"
git commit -q --allow-empty -m clean
sh scripts/check-public.sh --range "$base" HEAD 2>/dev/null; expect "leak in an earlier commit message" 1 $?
# The tree of the tip is scanned (scheduled runs use --range tip).
new_repo
mkdir -p docs; printf 'mario.rossi@gmail.\143om\n' > docs/note.md; git add docs; git commit -qm leak
sh scripts/check-public.sh --range tip HEAD 2>/dev/null;    expect "leak in the tip tree" 1 $?
# A leak introduced by a merge commit and removed afterwards.
new_repo
base=$(git rev-parse HEAD)
git switch -q -c side; mkdir -p docs; echo s > docs/side.md; git add docs; git commit -qm side; git switch -q main
git merge -q --no-ff --no-commit side >/dev/null 2>&1
printf 'mario.rossi@gmail.\143om\n' > docs/leak.md; git add docs; git commit -qm "merge with leak"
git rm -q docs/leak.md; git commit -qm "remove leak"
expect_reason "leak inside a merge commit" "docs/leak.md: email address" sh scripts/check-public.sh --range "$base" HEAD
# A leak in the root commit, removed afterwards (new branch, nothing on a remote).
rm -rf "$work/r" && mkdir -p "$work/r/scripts" && cd "$work/r" && git init -q -b main
cp "$src/check-public.sh" scripts/; mkdir -p docs; printf 'mario.rossi@gmail.\143om\n' > docs/leak.md
git add -A && git commit -qm root && git rm -q docs/leak.md && git commit -qm clean
expect_reason "leak in the root commit" "docs/leak.md: email address" sh scripts/check-public.sh --range remote:origin HEAD

# A leak added by modifying an existing file in a middle commit.
new_repo
mkdir -p docs; echo clean > docs/note.md; git add docs; git commit -qm note
base=$(git rev-parse HEAD)
printf 'mario.rossi@gmail.\143om\n' >> docs/note.md; git add docs; git commit -qm leak
echo clean > docs/note.md; git add docs; git commit -qm clean
expect_reason "leak in a modified file, middle commit" "docs/note.md: email address" sh scripts/check-public.sh --range "$base" HEAD
# Allowed folders accept only their own file types.
new_repo
staged "script with another extension" 1 scripts/x.py 'x\n'
staged "source with another extension" 1 src/notes.txt 'x\n'
sh scripts/audit-status.sh --bogus >/dev/null 2>&1;  expect "audit-status: unknown mode" 2 $?

# --- third review: boundaries and silent passes ---------------------------------------------
new_repo
staged "italian email (two-letter TLD)" 1 docs/note.md 'mario.rossi\100pec.comune.\151t\n'
staged "codice fiscale with omocodia"   1 docs/note.md 'RSSMRA80A01H50M\125\n'
staged "lower-case drive letter"        1 docs/note.md 'c:\\\125sers\\mrossi\n'
staged "slack user token"               1 src/x.rs '// xo\170p-123\n'
staged "docs name with a dot"           1 docs/a.b.md 'x\n'
staged "docs name in upper case"        1 docs/Note.md 'x\n'
staged "docs subfolder"                 1 docs/x/y.md 'x\n'
staged "github folder, not a workflow"  1 .github/notes.txt 'x\n'
staged "fixture name with a space"      1 'tests/fixtures/a b.p7m' 'x'
staged "other file in .cargo"           1 .cargo/credentials.toml 'x\n'
staged "other toml at the root"         1 secrets.toml 'x\n'
staged "other Cargo file"               1 Cargo.bak 'x\n'
staged "other .git file"                1 .gitmodules 'x\n'
staged "audit report allowed"           0 docs/audits/0009-2026-01-01.md 'x\n'
# A NUL inside a match: no category recognises it, the file is still blocked.
staged "NUL inside a match"             1 tests/fixtures/a.der 'x/\125sers/\000\n'
sh scripts/check-public.sh --message "$work/no-such-file" 2>/dev/null; expect "missing message file" 2 $?
sh scripts/check-public.sh --message "$work" 2>/dev/null;           expect "message path is a directory" 2 $?
sh scripts/check-public.sh --range remotes HEAD 2>/dev/null;            expect "old 'remotes' mode refused" 2 $?
# Shallow clones cannot see the history: never a pass.
new_repo
mkdir -p docs; echo a > docs/a.md; git add docs; git commit -qm a
git clone -q --depth 1 "file://$work/r" "$work/shallow" 2>/dev/null
(cd "$work/shallow" && sh scripts/check-public.sh --range "$(git rev-parse HEAD)" HEAD 2>/dev/null); expect "check-public: shallow clone" 2 $?
(cd "$work/shallow" && sh scripts/audit-status.sh --gate-push 2>/dev/null); expect "audit gate: shallow clone" 2 $?
(cd "$work/shallow" && echo x > s.txt && git add s.txt && sh scripts/audit-status.sh --gate-commit 2>/dev/null); expect "audit commit gate: shallow clone" 2 $?
rm -rf "$work/shallow"
# Only reports under docs/audits/ count as audits.
new_repo
commit a; commit b; commit c; commit d; commit e; commit f
mkdir -p docs; echo x > docs/other.md; git add docs; git commit -qm "not an audit"
sh scripts/audit-status.sh --gate-push 2>/dev/null;   expect "doc outside audits is not an audit" 1 $?
# The session report runs the cleanup as a dry run: it lists, it never deletes.
new_repo
echo junk > a.orig
out=$(sh scripts/audit-status.sh 2>/dev/null)
printf '%s\n' "$out" | grep -q "would remove junk file: a.orig"; expect "report lists leftovers" 0 $?
[ -f a.orig ];                                        expect "report deletes nothing" 0 $?
printf '%s\n' "$out" | grep -q "== Audit cadence";   expect "report printed" 0 $?
grep -q "^auth status" "$work/gh-stub.log" 2>/dev/null;  expect "the test stub stands in for the real gh" 0 $?
rm -f a.orig

# A grep failure is never a silent pass.
new_repo
mkdir -p "$work/shim"
printf '#!/bin/sh\ncase "$*" in *PRIVATE*) exit 2 ;; esac\nexec /usr/bin/grep "$@"\n' > "$work/shim/grep"
chmod +x "$work/shim/grep"
mkdir -p docs; printf 'mario.rossi@gmail.\143om\n' > docs/note.md; git add docs
PATH="$work/shim:$PATH" sh scripts/check-public.sh --staged 2>/dev/null; expect "grep error is not a pass" 2 $?
git reset -q; rm -rf docs

# The session report warns when the hooks are not enabled in this clone.
new_repo
sh scripts/audit-status.sh 2>/dev/null | grep -q "HOOKS NOT ENABLED"; expect "warning without hooks" 0 $?
git config core.hooksPath .githooks
out=$(sh scripts/audit-status.sh 2>/dev/null)
printf '%s\n' "$out" | grep -q "HOOKS NOT ENABLED"; expect "no warning with hooks" 1 $?
printf '%s\n' "$out" | grep -qx "== Audit cadence"; expect "report printed with hooks enabled" 0 $?
# The hooks path may also be the absolute path of this repository's own .githooks folder.
mkdir -p .githooks other
git config core.hooksPath "$(pwd)/.githooks"
out=$(sh scripts/audit-status.sh 2>/dev/null)
printf '%s\n' "$out" | grep -q "HOOKS NOT ENABLED"; expect "no warning with the absolute path of .githooks" 1 $?
printf '%s\n' "$out" | grep -qx "== Audit cadence"; expect "report printed with the absolute path of .githooks" 0 $?
# The same folder under another spelling counts: compared by identity, not by path text (Windows
# gives short 8.3 names such as RUNNER~1; a case-insensitive file system gives other letter case).
# Only a case-insensitive file system lets this test make the spelling differ.
if [ .githooks -ef .GITHOOKS ]; then
    git config core.hooksPath "$(pwd)/.GITHOOKS"
    out=$(sh scripts/audit-status.sh 2>/dev/null)
    printf '%s\n' "$out" | grep -q "HOOKS NOT ENABLED"; expect "no warning with another spelling of the same folder" 1 $?
    printf '%s\n' "$out" | grep -qx "== Audit cadence"; expect "report printed with another spelling of the same folder" 0 $?
fi
mkdir -p "$work/elsewhere/.githooks"
git config core.hooksPath "$work/elsewhere/.githooks"
sh scripts/audit-status.sh 2>/dev/null | grep -q "HOOKS NOT ENABLED"; expect "warning with a .githooks folder elsewhere" 0 $?
git config core.hooksPath "$(pwd)/other"
sh scripts/audit-status.sh 2>/dev/null | grep -q "HOOKS NOT ENABLED"; expect "warning with another folder of this repository" 0 $?
rmdir .githooks
git config core.hooksPath "$(pwd)/.githooks"
sh scripts/audit-status.sh 2>/dev/null | grep -q "HOOKS NOT ENABLED"; expect "warning with an absolute path to a missing .githooks" 0 $?
# A drive-letter path (git config stores C:/... in Git Bash) counts as absolute: it reaches the
# resolve step. On Windows, pwd -W gives this folder in that form. Elsewhere a symlink named
# "C:" in the current folder lets the resolve step succeed; such a name cannot exist on Windows.
mkdir .githooks
if dl=$(pwd -W 2>/dev/null) && [ -n "$dl" ]; then
    dl_hooks="$dl/.githooks"; dl_back=$(printf '%s\n' "$dl_hooks" | tr '/' '\\'); dl_other="$dl/other"
else
    ln -s . "C:"; ln -s .githooks 'C:\.githooks'; dl_links=yes
    dl_hooks="C:/.githooks"; dl_back='C:\.githooks'; dl_other="C:/other"
fi
git config core.hooksPath "$dl_hooks"
out=$(sh scripts/audit-status.sh 2>/dev/null)
printf '%s\n' "$out" | grep -q "HOOKS NOT ENABLED"; expect "no warning with a drive-letter path of .githooks" 1 $?
printf '%s\n' "$out" | grep -qx "== Audit cadence"; expect "report printed with a drive-letter path of .githooks" 0 $?
git config core.hooksPath "$dl_back"
out=$(sh scripts/audit-status.sh 2>/dev/null)
printf '%s\n' "$out" | grep -q "HOOKS NOT ENABLED"; expect "no warning with a drive-letter path, backslash" 1 $?
printf '%s\n' "$out" | grep -qx "== Audit cadence"; expect "report printed with a drive-letter path, backslash" 0 $?
git config core.hooksPath "$dl_other"
sh scripts/audit-status.sh 2>/dev/null | grep -q "HOOKS NOT ENABLED"; expect "warning with a drive-letter path of another folder" 0 $?
[ "${dl_links:-}" = yes ] && rm -f "C:" 'C:\.githooks'
rmdir .githooks
git config core.hooksPath .githooks

# The session report warns before the limit on who can open PRs and issues expires.
new_repo
git config core.hooksPath .githooks
mkdir -p "$work/ghshim"
fake_gh() { # fake_gh <expires_at or empty>
    printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *nameWithOwner*) echo owner/repo ;;\n  *interaction-limits*) printf "%%s\\n" "%s" ;;\n  *) exit 0 ;;\nesac\n' "$1" > "$work/ghshim/gh"
    chmod +x "$work/ghshim/gh"
}
soon=$(date -u -v+10d +%Y-%m-%d 2>/dev/null || date -u -d '+10 days' +%Y-%m-%d)
far=$(date -u -v+100d +%Y-%m-%d 2>/dev/null || date -u -d '+100 days' +%Y-%m-%d)
fake_gh "${soon}T00:00:00Z"
# The warning names the date only, not the full time stamp.
PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null |
    grep -q "^INTERACTION LIMIT EXPIRES on $soon: "
expect "limit expiring within 30 days" 0 $?
fake_gh "${far}T00:00:00Z"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null)
expect_absent "limit far away: no warning" GitHub "INTERACTION LIMIT" "$out"
report_section GitHub "$out" | grep -qx "no open pull requests"; expect "GitHub section ran (limit far away)" 0 $?
fake_gh ""
PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null | grep -q "INTERACTION LIMIT NOT ACTIVE"; expect "limit missing" 0 $?
# A failing gh api (network, API limit) is said, never read as a missing limit.
printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *nameWithOwner*) echo owner/repo ;;\n  *interaction-limits*) exit 1 ;;\n  *) exit 0 ;;\nesac\n' > "$work/ghshim/gh"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null)
report_section GitHub "$out" | grep -qx "interaction limit not read (gh api failed)"
expect "limit: a failing gh api is said" 0 $?
expect_absent "limit: a failing gh api is not a missing limit" GitHub "INTERACTION LIMIT NOT ACTIVE" "$out"
# The report says when a newer stable Rust exists than the pinned one (rust-toolchain.toml).
new_repo
printf '[toolchain]\nchannel = "1.100.0"\n' > rust-toolchain.toml
mkdir -p "$work/rustupshim"
# The stub lines copy the format of rustup 1.29.3 (rustup check), apart from the older-format test.
rustup_says() { printf '#!/bin/sh\n[ "$1" = check ] || exit 1\n%s\n' "$1" > "$work/rustupshim/rustup"; chmod +x "$work/rustupshim/rustup"; }
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - update available: 1.100.0 (a 2026-11-09) -> 1.101.0 (b 2026-12-21)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "NEWER RUST STABLE: 1.101.0 (pinned: 1.100.0); see rust-toolchain.toml"; expect "report: newer Rust stable shown" 0 $?
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: pinned Rust is the latest stable" 0 $?
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.99.0 (a 2026-10-01)'"
out=$(PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1)
printf '%s\n' "$out" | grep -q "NEWER RUST";            expect "report: an older installed stable is not newer" 1 $?
printf '%s\n' "$out" | grep -qx "pinned Rust 1.100.0; latest stable reported by rustup: 1.99.0"; expect "report: pinned ahead of the stable said" 0 $?
rm -f rust-toolchain.toml
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust version not found in rust-toolchain.toml"; expect "report: missing pin said" 0 $?
grep -q "^check" "$work/rustup-stub.log";               expect "the test stub stands in for the real rustup" 0 $?
printf '[toolchain]\nchannel = "1.100.0"\n' > rust-toolchain.toml
rustup_says "exit 1"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "Rust release not checked (rustup check failed, or no stable toolchain: rustup toolchain install stable)"; expect "report: rustup check failing is said" 0 $?
# Versions are compared number by number: patch 10 is after patch 9, major 10 after major 9.
printf '[toolchain]\nchannel = "1.100.9"\n' > rust-toolchain.toml
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - update available: 1.100.9 (a 2026-11-09) -> 1.100.10 (b 2026-11-20)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "NEWER RUST STABLE: 1.100.10 (pinned: 1.100.9); see rust-toolchain.toml"; expect "report: newer patch release shown" 0 $?
printf '[toolchain]\nchannel = "1.100.10"\n' > rust-toolchain.toml
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.9 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -q "NEWER RUST";     expect "report: older patch release is not newer" 1 $?
printf '[toolchain]\nchannel = "9.0.0"\n' > rust-toolchain.toml
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 10.0.0 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "NEWER RUST STABLE: 10.0.0 (pinned: 9.0.0); see rust-toolchain.toml"; expect "report: newer major release shown" 0 $?
printf '[toolchain]\nchannel = "1.100.0"\n' > rust-toolchain.toml
# Two hosts installed (e.g. arm64 and x86_64 on a Mac): rustup prints two stable lines, one is read.
rustup_says "printf '%s\\n' 'stable-aarch64-apple-darwin - update available: 1.100.0 (a 2026-11-09) -> 1.101.0 (b 2026-12-21)' 'stable-x86_64-apple-darwin - update available: 1.100.0 (a 2026-11-09) -> 1.101.0 (b 2026-12-21)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "NEWER RUST STABLE: 1.101.0 (pinned: 1.100.0); see rust-toolchain.toml"; expect "report: two stable lines read as one" 0 $?
# The line format of older rustup releases: "Up to date : X".
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - Up to date : 1.100.0 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: older rustup format read" 0 $?
# rustup gets no standard input, and its error text stays out of the report.
rustup_says "echo \"stdin=\$(cat)\" >> '$work/rustup-ask.log'; echo rustup-noise >&2; echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
rm -f "$work/rustup-ask.log"
out=$(echo typed | PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1)
[ "$(cat "$work/rustup-ask.log" 2>/dev/null)" = "stdin=" ];  expect "report: rustup reads no input" 0 $?
printf '%s\n' "$out" | grep -q "rustup-noise";             expect "report: rustup errors not shown" 1 $?
# Only the real channel line counts: not a commented one; tabs and single quotes are valid TOML.
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
printf '[toolchain]\n# channel = "1.0.0"\nchannel = "1.100.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: commented channel line ignored" 0 $?
printf "[toolchain]\nchannel\t= '1.100.0'\n" > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: tab and single quotes read" 0 $?
# A pin that is not x.y.z (e.g. "1.100" or "stable") is said, never compared.
printf '[toolchain]\nchannel = "1.100"\n' > rust-toolchain.toml
out=$(PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1)
printf '%s\n' "$out" | grep -qx "pinned Rust 1.100 is not x.y.z; see rust-toolchain.toml"; expect "report: pin without patch said" 0 $?
printf '%s\n' "$out" | grep -q "NEWER RUST";               expect "report: pin without patch not compared" 1 $?
printf '[toolchain]\nchannel = "1.100.0"\n' > rust-toolchain.toml
# Only stable lines count: a nightly line (cargo fuzz needs nightly) before the stable one is skipped.
rustup_says "printf '%s\\n' 'nightly-x86_64-unknown-linux-gnu - update available: 1.102.0-nightly (a 2026-11-20) -> 1.102.0-nightly (b 2026-11-22)' 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: nightly line skipped" 0 $?
rustup_says "printf '%s\\n' 'nightly-x86_64-unknown-linux-gnu - up to date: 1.102.0-nightly (a 2026-11-22)' 'stable-x86_64-unknown-linux-gnu - update available: 1.100.0 (a 2026-11-09) -> 1.101.0 (b 2026-12-21)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "NEWER RUST STABLE: 1.101.0 (pinned: 1.100.0); see rust-toolchain.toml"; expect "report: nightly up-to-date line skipped" 0 $?
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
# The whole pin must be x.y.z: a channel name or a pre-release is said, never compared.
printf '[toolchain]\nchannel = "stable"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust stable is not x.y.z; see rust-toolchain.toml"; expect "report: channel name said" 0 $?
printf '[toolchain]\nchannel = "1.100.0-beta.1"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0-beta.1 is not x.y.z; see rust-toolchain.toml"; expect "report: pre-release pin said" 0 $?
# Text after the closing quote is ignored: a trailing comment, CRLF line ends (Windows checkout).
printf '[toolchain]\nchannel = "1.100.0" # pinned\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: trailing comment ignored" 0 $?
printf '[toolchain]\r\nchannel = "1.100.0"\r\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: CRLF line ends read" 0 $?
# An indented key is valid TOML.
printf '[toolchain]\n  channel = "1.100.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: indented channel read" 0 $?
# A duplicate key (invalid TOML) still gives one line, from the first key.
printf '[toolchain]\nchannel = "1.99.0"\nchannel = "1.100.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "NEWER RUST STABLE: 1.100.0 (pinned: 1.99.0); see rust-toolchain.toml"; expect "report: first of two channel keys read" 0 $?
# Without the file, the "Rust" section is its heading and one line: no sed error text.
rm -f rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | sed -n '/^== Rust$/,/^== /p' > "$work/rust-section.txt"
printf '== Rust\npinned Rust version not found in rust-toolchain.toml\n\n== Unfinished local work\n' | cmp -s - "$work/rust-section.txt"; expect "report: Rust section is one line without the file" 0 $?
# White space around "=" is free in TOML: none, or a tab after it.
rustup_says "echo 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
printf '[toolchain]\nchannel="1.100.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: no spaces around = read" 0 $?
printf '[toolchain]\nchannel =\t"1.100.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: tab after = read" 0 $?
# The value ends at its closing quote, even when a comment after it holds the other quote.
printf "[toolchain]\nchannel = '1.100.0' # don't move\n" > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: apostrophe in a trailing comment" 0 $?
printf '[toolchain]\nchannel = "1.100.0" # was "1.99.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: double quotes in a trailing comment" 0 $?
printf '[toolchain]\n\tchannel = "1.100.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: tab-indented channel read" 0 $?
# A pin with an empty part is not x.y.z.
printf '[toolchain]\nchannel = "1.100."\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100. is not x.y.z; see rust-toolchain.toml"; expect "report: pin with an empty part said" 0 $?
printf '[toolchain]\nchannel = "1..0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1..0 is not x.y.z; see rust-toolchain.toml"; expect "report: pin with an empty middle part said" 0 $?
printf '[toolchain]\nchannel = ".100.0"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust .100.0 is not x.y.z; see rust-toolchain.toml"; expect "report: pin with an empty first part said" 0 $?
# A pin with a fourth number is not x.y.z.
printf '[toolchain]\nchannel = "1.100.0.1"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0.1 is not x.y.z; see rust-toolchain.toml"; expect "report: four-part pin said" 0 $?
printf '[toolchain]\nchannel = "1.100.0"\n' > rust-toolchain.toml
# With two stable hosts at different versions, the first line is read.
rustup_says "printf '%s\\n' 'stable-aarch64-apple-darwin - up to date: 1.100.0 (a 2026-11-09)' 'stable-x86_64-apple-darwin - update available: 1.100.0 (a 2026-11-09) -> 1.101.0 (b 2026-12-21)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: first of two stable hosts read" 0 $?
rustup_says "printf '%s\\n' 'stable-aarch64-apple-darwin - update available: 1.100.0 (a 2026-11-09) -> 1.101.0 (b 2026-12-21)' 'stable-x86_64-apple-darwin - up to date: 1.100.0 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "NEWER RUST STABLE: 1.101.0 (pinned: 1.100.0); see rust-toolchain.toml"; expect "report: first stable host read, not the lowest" 0 $?
# A pin problem is said before a rustup failure: the pin is the thing to fix first.
rustup_says "exit 1"
printf '[toolchain]\nchannel = "stable"\n' > rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust stable is not x.y.z; see rust-toolchain.toml"; expect "report: bad pin said before rustup failure" 0 $?
rm -f rust-toolchain.toml
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust version not found in rust-toolchain.toml"; expect "report: missing pin said before rustup failure" 0 $?
printf '[toolchain]\nchannel = "1.100.0"\n' > rust-toolchain.toml
# A toolchain whose name only contains "stable-" (a custom one) is not the stable channel.
rustup_says "printf '%s\\n' 'my-stable-x86_64-unknown-linux-gnu - up to date: 1.50.0 (a 2025-01-01)' 'my-stable-x86_64-unknown-linux-gnu - update available: 1.50.0 (a 2025-01-01) -> 1.51.0 (b 2025-02-01)' 'stable-x86_64-unknown-linux-gnu - up to date: 1.100.0 (a 2026-11-09)'"
PATH="$work/rustupshim:$PATH" sh scripts/audit-status.sh 2>&1 | grep -qx "pinned Rust 1.100.0 is the latest stable"; expect "report: custom toolchain named *stable- skipped" 0 $?
printf '[toolchain]\nchannel = "1.100.0"\n' > rust-toolchain.toml
# The report says when an audit is due (5 commits since the last one), and not before.
new_repo
commit a; commit b; commit c; commit d
expect_absent "report: 4 commits, no AUDIT DUE" "Audit cadence" "^AUDIT DUE$" "$(sh scripts/audit-status.sh 2>&1)"
commit e
sh scripts/audit-status.sh 2>&1 | grep -qx "AUDIT DUE";  expect "report: 5 commits, AUDIT DUE" 0 $?
# Red checks on open pull requests: see the section "step 0.5" at the end.
# A tag called "main" does not hide unmerged branches or garble branch names in the report.
new_repo
git switch -q -c feat && echo f > f.txt && git add f.txt && git commit -qm feat && git tag main feat && git tag feat
git init -q --bare "$work/origin.git"; git remote add origin "$work/origin.git"
git push -q origin refs/heads/main refs/heads/feat 2>/dev/null; git fetch -q origin; git remote set-head origin feat; git tag origin/main feat
out=$(sh scripts/audit-status.sh 2>&1)
printf '%s\n' "$out" | grep -A1 "local branches not merged into main:" | grep -qx "  feat"; expect "report: tag main does not hide unmerged branches" 0 $?
printf '%s\n' "$out" | grep -q "^branch feat:";       expect "report: current branch named without heads/" 0 $?
printf '%s\n' "$out" | grep -A3 "remote branches not merged into main:" | grep -qx "  origin/feat"; expect "report: unmerged remote branch listed" 0 $?
expect_absent "report: no origin/HEAD or origin/main line" "Unfinished local work" "^  origin/(HEAD|main)$" "$out"
expect_absent "report: only branches listed, no tags or other refs" "Unfinished local work" "refs/" "$out"
# Without origin/main the remote list says it cannot check, instead of staying silent.
git update-ref -d refs/remotes/origin/main
sh scripts/audit-status.sh 2>&1 | grep -q "no origin/main: unmerged remote branches not checked"; expect "report: missing origin/main is said" 0 $?
rm -rf "$work/origin.git"
# With no origin remote there is nothing to say about remote branches.
git remote remove origin
expect_absent "report: no origin remote, no origin/main line" "Unfinished local work" "no origin/main" "$(sh scripts/audit-status.sh 2>&1)"
# Without a local branch main the report says it cannot check, instead of staying silent.
git branch -q -m main trunk
sh scripts/audit-status.sh 2>&1 | grep -q "no local branch main: unmerged local branches not checked"; expect "report: missing main is said" 0 $?
git branch -q -m trunk main
# gh can never ask or read input in the session report: every call has no prompt, no stdin.
printf '#!/bin/sh\necho "prompt=${GH_PROMPT_DISABLED:-} stdin=$(cat)" >> "%s/gh-ask.log"\nexit 0\n' "$work" > "$work/ghshim/gh"
rm -f "$work/gh-ask.log"
echo typed | PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh >/dev/null 2>&1
[ -s "$work/gh-ask.log" ] && ! grep -vx "prompt=1 stdin=" "$work/gh-ask.log" | grep -q .; expect "report: gh never prompts or reads input" 0 $?

# --- step 0.5: check-public.sh git failures ------------------------------------------------
# What happens when git fails inside check-public.sh? It stops with exit 2 and names the failed
# command, never a silent pass. A git wrapper on PATH fails for one subcommand only and runs
# the real git for everything else.
gf_git=$(command -v git)
mkdir -p "$work/gf-shim"
gf_fail() { # gf_fail <word>: the wrapper fails whenever one of its arguments is that word
    printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = %s ] && { echo "fatal: test failure" >&2; exit 128; }; done\nexec "%s" "$@"\n' \
        "$1" "$gf_git" > "$work/gf-shim/git"
    chmod +x "$work/gf-shim/git"
}
# gf_expect <description> <reason in stderr> <check-public.sh arguments...>: exit 2 for that reason.
gf_expect() {
    gf_desc=$1; gf_reason=$2; shift 2
    gf_err=$(PATH="$work/gf-shim:$PATH" sh scripts/check-public.sh "$@" 2>&1 >/dev/null); gf_r=$?
    if [ "$gf_r" -eq 2 ] && printf '%s\n' "$gf_err" | grep -q "$gf_reason"; then passed=$((passed + 1)); else
        failed=$((failed + 1)); echo "FAIL: $gf_desc (exit $gf_r, expected 2 with \"$gf_reason\"; got: $gf_err)" >&2; fi
}
new_repo
mkdir -p docs; echo a > docs/a.md; git add docs; git commit -qm a
gf_base=$(git rev-parse HEAD~1)
# Control: the wrapper itself runs git normally when the failing subcommand is not used.
gf_fail no-such-subcommand
PATH="$work/gf-shim:$PATH" sh scripts/check-public.sh --range "$gf_base" HEAD >/dev/null 2>&1
expect "git failures: the wrapper alone passes a clean range" 0 $?
gf_fail show
echo b > docs/b.md; git add docs
gf_expect "git show fails on a staged file"      "cannot check: cannot read :docs/b.md" --staged
git reset -q; rm -f docs/b.md
gf_expect "git show fails on a file of the range" "cannot check: cannot read $(git rev-parse HEAD):" --range "$gf_base" HEAD
gf_fail ls-tree
gf_expect "git ls-tree fails on the tip tree"     "cannot check: git ls-tree failed on HEAD" --range tip HEAD
git switch -q -c gf-side; echo c > docs/c.md; git add docs; git commit -qm c
git switch -q main; git merge -q --no-ff --no-edit gf-side
gf_expect "git ls-tree fails on a merge commit"   "cannot check: git ls-tree failed on $(git rev-parse HEAD)" --range "$gf_base" HEAD
gf_fail diff-tree
gf_expect "git diff-tree fails on a commit"       "cannot check: git diff-tree failed on" --range "$gf_base" HEAD
# A failing git rev-list --parents must stop the run, also for a merge commit (whose files are
# listed from the whole tree): the count of parents is never taken from a failed command.
gf_fail --parents
gf_expect "git rev-list --parents fails on a merge commit" "cannot check: git rev-list failed on $(git rev-parse HEAD)" --range "$gf_base" HEAD
gf_fail log
gf_expect "git log fails on a commit"             "cannot check: git log failed on" --range "$gf_base" HEAD
gf_fail "$gf_base..HEAD"
gf_expect "git rev-list fails on a range"         "cannot check: git rev-list failed$" --range "$gf_base" HEAD
gf_fail --not
gf_expect "git rev-list fails on a remote range"  "cannot check: git rev-list failed$" --range remote:origin HEAD
gf_fail diff
gf_expect "git diff fails on the staged files"    "cannot check: git diff failed" --staged
# Annotated tags, also nested: reading the type or the content of each tag can fail too.
git tag -a gf-inner -m inner; git tag -a gf-outer -m outer gf-inner 2>/dev/null
gf_fail no-such-subcommand
PATH="$work/gf-shim:$PATH" sh scripts/check-public.sh --range tip gf-outer >/dev/null 2>&1
expect "git failures: the wrapper alone passes nested tags" 0 $?
gf_fail cat-file
gf_expect "git cat-file fails on the type of a tag" "cannot check: cannot read object gf-outer" --range tip gf-outer
gf_fail tag
gf_expect "git cat-file fails on an outer tag"      "cannot check: cannot read tag gf-outer" --range tip gf-outer
# The inner tag is reached by its id: the wrapper fails only for that id.
gf_inner=$(git rev-parse gf-inner)
gf_fail "$gf_inner"
gf_expect "git cat-file fails on an inner tag"      "cannot check: cannot read object $gf_inner" --range tip gf-outer

# --- step 0.5: audit-status.sh gaps ---------------------------------------------------------
new_repo
# gh_checks <file>: a logged-in gh with one open pull request. For the checks of the open pull
# requests it returns the file, one line per check, as the script's own gh call returns them.
# The fields are number, type, workflow, name, conclusion, state and start time, separated by
# tabs. The script selects the red ones.
gh_checks() {
    printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *statusCheckRollup*) cat "%s" ;;\n  *isDraft*) echo "#2 open step/x updated 2026-11-24: Test" ;;\n  *) exit 0 ;;\nesac\n' "$1" > "$work/ghshim/gh"
    chmod +x "$work/ghshim/gh"
}
# Owner's decision of 2026-11-24: everything that is not green is red. The rule is an allowlist:
# a check run is red when its conclusion is not empty and not SUCCESS, NEUTRAL or SKIPPED; a
# commit status is red when its state is not empty and not SUCCESS, PENDING or EXPECTED. So
# STALE, and any value GitHub adds later, is red. Running or pending ones (empty conclusion,
# PENDING, EXPECTED) are not red yet. The values are compared whole.
t='	'
{
    printf '2%sCheckRun%s%sLint%sFAILURE%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sBuild%sSUCCESS%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sTest (a)%sCANCELLED%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sTest (b)%sTIMED_OUT%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sDeploy%sACTION_REQUIRED%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sDocs%sSTARTUP_FAILURE%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sFmt%sNEUTRAL%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sFuzz%sSKIPPED%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sStill running%s%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/a%s%sERROR\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/b%s%sFAILURE\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/c%s%sPENDING\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/d%s%sSUCCESS\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/e%s%sEXPECTED\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sStale one%sSTALE%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sNew one%sWEIRD_NEW%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/s%s%sSTALE\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/w%s%sWEIRD_NEW\n' "$t" "$t" "$t" "$t" "$t"
    printf '5%sCheckRun%s%sBuild%sSUCCESS%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '5%sCheckRun%s%sQueued%s%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '5%sStatusContext%s%sci/x%s%sPENDING\n' "$t" "$t" "$t" "$t" "$t"
    printf '7%sStatusContext%s%sci/z%s%sERROR\n' "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-red.tsv"
gh_checks "$work/checks-red.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#2 failing: Lint, Test (a), Test (b), Deploy, Docs, ci/a, ci/b, Stale one, New one, ci/s, ci/w\n#7 failing: ci/z\n' | cmp -s - "$work/red.txt"; expect "report: red checks selected (not green, not pending)" 0 $?
# Owner's decision of 2026-11-25: for each check of a pull request, only its latest attempt
# counts. The latest is the one that started last; one not started yet (no start time, or
# GitHub's zero time) is the latest. The lines are not in time order: the script must compare
# the times. A check of the same name on another pull request does not count.
{
    printf '3%sCheckRun%s%sLint%sFAILURE%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sLint%sSUCCESS%s%s2026-11-24T11:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sTest%sFAILURE%s%s2026-11-24T12:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sTest%sSUCCESS%s%s2026-11-24T09:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sBuild%sFAILURE%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sBuild%s%s%s0001-01-01T00:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sDocs%sFAILURE%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sDocs%s%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sStatusContext%s%sci/a%s%sERROR%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sStatusContext%s%sci/a%s%sSUCCESS%s2026-11-24T11:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sStatusContext%s%sci/b%s%sSUCCESS%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sStatusContext%s%sci/b%s%sFAILURE%s2026-11-24T11:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sEq-a%sFAILURE%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sEq-a%sSUCCESS%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sEq-b%sSUCCESS%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sEq-b%sFAILURE%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sStatusContext%s%sci/g1%sFAILURE%sSUCCESS%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sG2%sSUCCESS%sERROR%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sG3%sSUCCESS_X%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sCheckRun%s%sG4%sXSUCCESS%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sStatusContext%s%sci/g5%s%sPENDINGISH%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '3%sStatusContext%s%sci/g6%s%sXEXPECTED%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '9%sCheckRun%sCI%sbuild%sFAILURE%s%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '9%sCheckRun%sDocs%sbuild%sSUCCESS%s%s2026-11-24T10:00:05Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '8%sCheckRun%s%sTest%sSUCCESS%s%s2026-11-24T13:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-rerun.tsv"
gh_checks "$work/checks-rerun.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#3 failing: Test, ci/b, Eq-b, G3, G4, ci/g5, ci/g6\n#9 failing: CI / build\n' | cmp -s - "$work/red.txt"; expect "report: only the latest attempt of each check counts" 0 $?
# Each type has its own green list: PENDING and EXPECTED are green only for a status, NEUTRAL and
# SKIPPED only for a check run. A value from the other list is red.
{
    printf '2%sCheckRun%s%sCR-pending%sPENDING%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sCR-expected%sEXPECTED%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sst-neutral%s%sNEUTRAL%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sst-skipped%s%sSKIPPED%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-lists.tsv"
gh_checks "$work/checks-lists.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#2 failing: CR-pending, CR-expected, st-neutral, st-skipped\n' | cmp -s - "$work/red.txt"; expect "report: each type has its own green list" 0 $?
# A commit status and a check run that has no workflow have the same (empty) workflow: the type
# is part of the key, so a green check run never hides a red status of the same name.
{
    printf '4%sCheckRun%s%sci%sSUCCESS%s%s2026-11-24T11:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '4%sStatusContext%s%sci%s%sFAILURE%s2026-11-24T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-type.tsv"
gh_checks "$work/checks-type.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#4 failing: ci\n' | cmp -s - "$work/red.txt"; expect "report: a red status is not hidden by a green check run of the same name" 0 $?
# A row of a type the script does not know is judged by the same rule: red when its conclusion
# or its state is not empty and not a green value of either list (SUCCESS, NEUTRAL, SKIPPED,
# PENDING, EXPECTED); not red when both are empty.
{
    printf '6%sOther%s%sunk/red1%sFAILURE%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/red2%s%sERROR\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/red3%sSUCCESS%sSTALE\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/ok1%s%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/ok2%sNEUTRAL%sEXPECTED\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/ok3%sPENDING%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/red4%sSUCCESS_X%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/red5%s%sXPENDING\n' "$t" "$t" "$t" "$t" "$t"
    printf '6%sOther%s%sunk/red6%sSTALE%s\n' "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-unknown.tsv"
gh_checks "$work/checks-unknown.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#6 failing: unk/red1, unk/red2, unk/red3, unk/red4, unk/red5, unk/red6\n' | cmp -s - "$work/red.txt"; expect "report: a row of an unknown type is red unless green or empty" 0 $?
# A failing gh pr list (network, API limit) is said, never silent.
printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *statusCheckRollup*) echo "API rate limit exceeded" >&2; exit 1 ;;\n  *isDraft*) echo "#2 open step/x updated 2026-11-24: Test" ;;\n  *) exit 0 ;;\nesac\n' > "$work/ghshim/gh"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | grep -qx "checks not read (gh pr list failed)"; expect "report: a failing gh pr list is said" 0 $?
# A check that finished and has no start time is older than any check with a time; between
# finished checks without a time, the later line wins. Only a check that is not started yet
# (no conclusion, no state) counts as the latest without a time.
{
    printf '2%sCheckRun%s%sLint%sSUCCESS%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sLint%sFAILURE%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sBuild%sFAILURE%s%s0001-01-01T00:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sBuild%sSUCCESS%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sDocs%sSUCCESS%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sDocs%sFAILURE%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sFmt%sFAILURE%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sFmt%sSUCCESS%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-notime.tsv"
gh_checks "$work/checks-notime.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#2 failing: Lint, Docs\n' | cmp -s - "$work/red.txt"; expect "report: a finished check with no time is older than one with a time" 0 $?
# The same holds for commit statuses: a finished status with no time is older than one with a
# time, in either line order.
{
    printf '2%sStatusContext%s%sci/x%s%sSUCCESS%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/x%s%sFAILURE%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/y%s%sFAILURE%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/y%s%sSUCCESS%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-notime-status.tsv"
gh_checks "$work/checks-notime-status.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#2 failing: ci/x, ci/y\n' | cmp -s - "$work/red.txt"; expect "report: a finished status with no time is older than one with a time" 0 $?
# A check not started yet is the latest in either line order.
{
    printf '2%sCheckRun%s%sLint%s%s%s\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sLint%sFAILURE%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sBuild%s%s%s0001-01-01T00:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sBuild%sFAILURE%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-order.tsv"
gh_checks "$work/checks-order.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
expect_absent "report: a check not started yet is the latest, also when listed first" GitHub "RED CHECKS" "$out"
# Two red checks of the same name in two workflows are told apart, and a red check with no name
# is said.
{
    printf '9%sCheckRun%sCI%sbuild%sFAILURE%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '9%sCheckRun%sDocs%sbuild%sFAILURE%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '9%sCheckRun%s%slint%sFAILURE%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
    printf '9%sCheckRun%s%s%sFAILURE%s%s2026-11-25T10:00:00Z\n' "$t" "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-names.tsv"
gh_checks "$work/checks-names.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^RED CHECKS/ { on = 1; print; next } on && /^#/ { print; next } { on = 0 }' > "$work/red.txt"
printf 'RED CHECKS on open pull requests:\n#9 failing: CI / build, Docs / build, lint, (no name)\n' | cmp -s - "$work/red.txt"; expect "report: red checks named with workflow, empty name said" 0 $?
# A failing gh pr list is said, never silent.
printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *"pr list"*) echo "API rate limit exceeded" >&2; exit 1 ;;\n  *) exit 0 ;;\nesac\n' > "$work/ghshim/gh"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | grep -qx "open pull requests not read (gh pr list failed)"; expect "report: a failing gh pr list says open pull requests not read" 0 $?
expect_absent "report: a failing gh pr list does not say no open pull requests" GitHub "^no open pull requests" "$out"
# A failing gh run list is said too, and does not claim there are no runs.
printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *"run list"*) echo "HTTP 502" >&2; exit 1 ;;\n  *) exit 0 ;;\nesac\n' > "$work/ghshim/gh"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | grep -qx "CI runs not read (gh run list failed)"; expect "report: a failing gh run list says CI runs not read" 0 $?
expect_absent "report: a failing gh run list does not say no CI runs" GitHub "^no CI runs on main" "$out"
# A gh run list with runs prints them, exactly, under the heading. With no runs it says so.
printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *"run list"*) printf "%%s\\n" "2026-11-25 completed/success: Run one" "2026-11-24 in_progress/-: Run two" ;;\n  *) exit 0 ;;\nesac\n' > "$work/ghshim/gh"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | awk '/^last CI runs on main:$/ { on = 1; print; next } on { print }' > "$work/runs.txt"
printf 'last CI runs on main:\n2026-11-25 completed/success: Run one\n2026-11-24 in_progress/-: Run two\n' | cmp -s - "$work/runs.txt"; expect "report: last CI runs listed under the heading" 0 $?
printf '#!/bin/sh\ncase "$*" in\n  "auth status"*) exit 0 ;;\n  *) exit 0 ;;\nesac\n' > "$work/ghshim/gh"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | grep -qx "no CI runs on main"; expect "report: no CI runs said" 0 $?
# Only green, pending and running checks: the GitHub section runs, and has no RED CHECKS line.
{
    printf '2%sCheckRun%s%sBuild%sSUCCESS%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sFmt%sNEUTRAL%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sFuzz%sSKIPPED%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sCheckRun%s%sStill running%s%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/c%s%sPENDING\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/d%s%sSUCCESS\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/e%s%sEXPECTED\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sStatusContext%s%sci/f%s%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/a%s%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/b%sSUCCESS%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/c%s%sEXPECTED\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/d%sSKIPPED%sPENDING\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/e%sEXPECTED%s\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/f%s%sSUCCESS\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/g%s%sNEUTRAL\n' "$t" "$t" "$t" "$t" "$t"
    printf '2%sOther%s%sunk/h%s%sSKIPPED\n' "$t" "$t" "$t" "$t" "$t"
} > "$work/checks-green.tsv"
gh_checks "$work/checks-green.tsv"
out=$(PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>&1)
report_section GitHub "$out" | grep -qx "#2 open step/x updated 2026-11-24: Test"; expect "report: GitHub section ran with the gh stub" 0 $?
report_section GitHub "$out" | grep -qx "open pull requests:"; expect "report: open pull requests heading printed" 0 $?
expect_absent "report: no red checks, no RED CHECKS line" GitHub "RED CHECKS" "$out"
# Unfinished local work: uncommitted changes, stashes, unpushed and not pulled commits.
new_repo
commit a
out=$(sh scripts/audit-status.sh 2>&1)
report_section "Unfinished local work" "$out" | grep -qx "working tree clean"; expect "report: clean working tree said" 0 $?
expect_absent "report: clean tree, no uncommitted changes" "Unfinished local work" "^uncommitted changes:" "$out"
expect_absent "report: no stash, no stashes line" "Unfinished local work" "^stashes:" "$out"
report_section "Unfinished local work" "$out" | grep -qx "branch main: no upstream"; expect "report: no upstream said" 0 $?
echo changed > a.txt; echo new > new.txt
out=$(sh scripts/audit-status.sh 2>&1)
report_section "Unfinished local work" "$out" | grep -A2 -x "uncommitted changes:" > "$work/dirty.txt"
printf 'uncommitted changes:\n M a.txt\n?? new.txt\n' | cmp -s - "$work/dirty.txt"; expect "report: uncommitted changes listed" 0 $?
expect_absent "report: changes, no working tree clean" "Unfinished local work" "^working tree clean$" "$out"
git stash push -q -m "test stash"
out=$(sh scripts/audit-status.sh 2>&1)
report_section "Unfinished local work" "$out" | grep -A1 -x "stashes:" > "$work/stashes.txt"
printf 'stashes:\nstash@{0}: On main: test stash\n' | cmp -s - "$work/stashes.txt"; expect "report: stash listed" 0 $?
git stash drop -q; rm -f new.txt
# Upstream counts: commits not pushed, and commits fetched but not pulled.
git init -q --bare -b main "$work/up.git"; git remote add origin "$work/up.git"
git push -q -u origin main 2>/dev/null
commit b; commit c
report_section "Unfinished local work" "$(sh scripts/audit-status.sh 2>&1)" | grep -qx "branch main: 2 unpushed, 0 not pulled"; expect "report: unpushed commits counted" 0 $?
git clone -q "$work/up.git" "$work/other" 2>/dev/null
(cd "$work/other" && commit x && commit y && commit z && git push -q origin main 2>/dev/null)
git fetch -q origin
report_section "Unfinished local work" "$(sh scripts/audit-status.sh 2>&1)" | grep -qx "branch main: 2 unpushed, 3 not pulled"; expect "report: not pulled commits counted" 0 $?
rm -rf "$work/up.git" "$work/other"

# Markers in code: src and tests are searched, tracked or not. The fixtures are skipped, and so
# are tests/corpus/ and tests/out/, which hold real and extracted documents, even when
# .gitignore lacks them (audit 0011, F1).
new_repo
mkdir -p src tests/fixtures tests/corpus tests/out
printf '// TODO tracked marker\n' > src/lib.rs
printf '// FIXME untracked marker\n' > tests/new.rs
printf 'TODO fixture line\n' > tests/fixtures/f.txt
printf 'TODO corpus line\n' > tests/corpus/c.txt
printf 'XXX extracted line\n' > tests/out/o.txt
# Binary files, as real signed documents are: a search that reads them prints their names.
printf 'TODO\000corpus binary\n' > tests/corpus/b.p7m
printf 'TODO\000extracted binary\n' > tests/out/b.pdf
git add src/lib.rs && git commit -qm markers
out=$(sh scripts/audit-status.sh 2>/dev/null)
report_section "Markers in code" "$out" | grep -q '^src/lib.rs:1:// TODO tracked marker$'
expect "markers: a tracked file in src is listed" 0 $?
report_section "Markers in code" "$out" | grep -q '^tests/new.rs:1:// FIXME untracked marker$'
expect "markers: an untracked file in tests is listed" 0 $?
expect_absent "markers: fixtures, corpus and output skipped" "Markers in code" \
    'fixtures|corpus|tests/out|extracted' "$out"
# Each marker word is listed.
printf '// XXX word\ntodo!(a)\nunimplemented!(b)\n#[ignore]\n' > src/words.rs
out=$(sh scripts/audit-status.sh 2>/dev/null)
for w in "src/words.rs:1:// XXX word" "src/words.rs:2:todo!(a)" "src/words.rs:3:unimplemented!(b)" \
    "src/words.rs:4:#[ignore]"; do
    report_section "Markers in code" "$out" | grep -qxF "$w"; expect "markers: listed: $w" 0 $?
done
# With a single file to search, the line still starts with the file name.
rm -f src/lib.rs src/words.rs tests/new.rs
printf '// XXX alone\n' > src/one.rs
out=$(sh scripts/audit-status.sh 2>/dev/null)
report_section "Markers in code" "$out" | grep -qxF "src/one.rs:1:// XXX alone"
expect "markers: a single file is named" 0 $?
# The two folders are skipped whatever the case of their names: on macOS and Windows,
# tests/CORPUS is tests/corpus. Every letter is in capitals here and in lower case in the test
# above, so a pattern that drops either case of any letter fails. Only the capital folders exist
# here, so the test also holds on Linux, where the names differ.
new_repo
mkdir -p src tests/CORPUS tests/OUT
printf '// TODO kept\n' > src/lib.rs
printf 'XXX cased corpus\n' > tests/CORPUS/c.txt
printf 'TODO\000cased binary\n' > tests/OUT/o.pdf
out=$(sh scripts/audit-status.sh 2>/dev/null)
report_section "Markers in code" "$out" | grep -qxF "src/lib.rs:1:// TODO kept"
expect "markers: cased folders: the search ran" 0 $?
expect_absent "markers: cased corpus and output skipped" "Markers in code" 'CORPUS|OUT|cased' "$out"
# Symbolic links into the corpus are not followed: a link to a corpus file and a link to the
# corpus folder print nothing. Git Bash on Windows may copy instead of linking; there the test
# is skipped, and only there.
new_repo
mkdir -p src tests/corpus
printf '// TODO kept\n' > src/lib.rs
printf 'XXX linked corpus\n' > tests/corpus/c.txt
ln -s corpus/c.txt tests/filelink.txt 2>/dev/null
ln -s ../tests/corpus src/dirlink 2>/dev/null
if [ -L tests/filelink.txt ] && [ -L src/dirlink ]; then
    out=$(sh scripts/audit-status.sh 2>/dev/null)
    report_section "Markers in code" "$out" | grep -qxF "src/lib.rs:1:// TODO kept"
    expect "markers: links: the search ran" 0 $?
    expect_absent "markers: links into the corpus not followed" "Markers in code" 'linked' "$out"
elif pwd -W >/dev/null 2>&1; then
    echo "skipped on Windows: ln -s made no symbolic link"
else
    expect "markers: symbolic links created" 0 1
fi
# The files of the two folders are never read, not only hidden from the output. A grep
# stand-in logs every recursive option and every argument that names an existing file, then
# runs the real grep. Grep reads a folder only when it searches recursively. Patterns, such as
# the one cleanup.sh uses to protect these folders, name no file and are not logged.
new_repo
mkdir -p src tests/corpus tests/out tests/CORPUS "$work/grepshim"
printf '// TODO kept\n' > src/lib.rs
printf 'XXX corpus\n' > tests/corpus/c.txt
printf 'XXX upper corpus\n' > tests/CORPUS/c.txt
printf 'TODO\000out binary\n' > tests/out/o.pdf
real_grep=$(command -v grep)
rm -f "$work/grep.log"
printf '#!/bin/sh\nfor a in "$@"; do\n  case "$a" in\n    --recursive|--dereference-recursive) echo "recursive: $a" ;;\n    --*) ;;\n    -*[rR]*) echo "recursive: $a" ;;\n  esac >> "%s/grep.log"\n  [ -f "$a" ] && echo "path: $a" >> "%s/grep.log"\ndone\nexec "%s" "$@"\n' \
    "$work" "$work" "$real_grep" > "$work/grepshim/grep"
chmod +x "$work/grepshim/grep"
out=$(PATH="$work/grepshim:$PATH" sh scripts/audit-status.sh 2>/dev/null)
grep -qx "path: src/lib.rs" "$work/grep.log"; expect "markers: grep stand-in was used" 0 $?
grep -Eiq '^recursive: |tests/(corpus|out)' "$work/grep.log"
expect "markers: no recursive grep and no corpus or output file given to grep" 1 $?
# A repository with no marker says so.
new_repo
mkdir -p src; printf 'fn main() {}\n' > src/main.rs
out=$(sh scripts/audit-status.sh 2>/dev/null)
[ "$(report_section "Markers in code" "$out")" = none ]; expect "markers: none said" 0 $?
# A grep that cannot run is said, never read as "no markers". The stand-in fails as grep does
# on an error (exit 2); the other grep calls of the report keep the real grep.
mkdir -p "$work/badgrep"
printf '#!/bin/sh\ncase "$*" in *TODO*FIXME*) echo "grep: broken" >&2; exit 2 ;; esac\nexec "%s" "$@"\n' \
    "$real_grep" > "$work/badgrep/grep"
chmod +x "$work/badgrep/grep"
out=$(PATH="$work/badgrep:$PATH" sh scripts/audit-status.sh 2>/dev/null)
[ "$(report_section "Markers in code" "$out")" = "markers not read (find or grep failed)" ]
expect "markers: a failing grep is said" 0 $?
# Any exit above 1 is a failure, not only 2: a grep that is missing exits 127.
printf '#!/bin/sh\ncase "$*" in *TODO*FIXME*) exit 127 ;; esac\nexec "%s" "$@"\n' "$real_grep" \
    > "$work/badgrep/grep"
out=$(PATH="$work/badgrep:$PATH" sh scripts/audit-status.sh 2>/dev/null)
[ "$(report_section "Markers in code" "$out")" = "markers not read (find or grep failed)" ]
expect "markers: a grep that exits 127 is said" 0 $?
# Markers found before a failure are still listed, followed by the failure.
printf '// TODO found\n' > src/main.rs
printf '#!/bin/sh\ncase "$*" in *TODO*FIXME*) "%s" "$@"; exit 2 ;; esac\nexec "%s" "$@"\n' \
    "$real_grep" "$real_grep" > "$work/badgrep/grep"
out=$(PATH="$work/badgrep:$PATH" sh scripts/audit-status.sh 2>/dev/null)
[ "$(report_section "Markers in code" "$out")" = "src/main.rs:1:// TODO found
some files not read (find or grep failed)" ]
expect "markers: found markers listed before a failure" 0 $?
# A repository with neither src nor tests has nothing to search.
new_repo
out=$(sh scripts/audit-status.sh 2>/dev/null)
[ "$(report_section "Markers in code" "$out")" = none ]
expect "markers: no src, no tests: none" 0 $?
# A root that is a file, not a folder, is still searched.
printf '// TODO in a file named src\n' > src
out=$(sh scripts/audit-status.sh 2>/dev/null)
[ "$(report_section "Markers in code" "$out")" = "src:1:// TODO in a file named src" ]
expect "markers: a root that is a file is searched" 0 $?
rm -f src
# A failure of find itself: the stand-in runs the real find, then exits 1, as find does when a
# folder cannot be read. Markers found are listed, then the failure.
new_repo
mkdir -p src "$work/badfind"; printf '// TODO open\n' > src/open.rs
real_find=$(command -v find)
printf '#!/bin/sh\n"%s" "$@"\ncase "$*" in *TODO*FIXME*) exit 1 ;; esac\n' "$real_find" \
    > "$work/badfind/find"
chmod +x "$work/badfind/find"
out=$(PATH="$work/badfind:$PATH" sh scripts/audit-status.sh 2>/dev/null)
[ "$(report_section "Markers in code" "$out")" = "src/open.rs:1:// TODO open
some files not read (find or grep failed)" ]
expect "markers: a failing find is said" 0 $?
# A root that is a symbolic link is not followed, since it could lead into the corpus. The
# search says so on a line of its own, not as a failure of find or grep, and still reads the
# other root. Git Bash on Windows may copy instead of linking; there the test is skipped, and
# only there.
new_repo
mkdir -p real; printf '// TODO behind a link\n' > real/a.rs
ln -s real src 2>/dev/null
if [ -L src ]; then
    out=$(sh scripts/audit-status.sh 2>/dev/null)
    [ "$(report_section "Markers in code" "$out")" = "src: symbolic link, not searched" ]
    expect "markers: a linked root is named" 0 $?
    mkdir -p tests; printf 'fn b() {}\n' > tests/b.rs
    out=$(sh scripts/audit-status.sh 2>/dev/null)
    [ "$(report_section "Markers in code" "$out")" = "src: symbolic link, not searched
none" ]
    expect "markers: a linked root beside a clean root" 0 $?
    printf '// TODO beside the link\n' > tests/b.rs
    out=$(sh scripts/audit-status.sh 2>/dev/null)
    [ "$(report_section "Markers in code" "$out")" = "src: symbolic link, not searched
tests/b.rs:1:// TODO beside the link" ]
    expect "markers: a linked root beside a real root" 0 $?
    # A root that is a symbolic link and a failing grep: the failure is still said, never "none".
    printf 'fn b() {}\n' > tests/b.rs
    printf '#!/bin/sh\ncase "$*" in *TODO*FIXME*) exit 2 ;; esac\nexec "%s" "$@"\n' "$real_grep" \
        > "$work/badgrep/grep"
    out=$(PATH="$work/badgrep:$PATH" sh scripts/audit-status.sh 2>/dev/null)
    [ "$(report_section "Markers in code" "$out")" = "src: symbolic link, not searched
markers not read (find or grep failed)" ]
    expect "markers: a linked root and a failing grep" 0 $?
    printf '// TODO before a failure\n' > tests/b.rs
    printf '#!/bin/sh\ncase "$*" in *TODO*FIXME*) "%s" "$@"; exit 2 ;; esac\nexec "%s" "$@"\n' \
        "$real_grep" "$real_grep" > "$work/badgrep/grep"
    out=$(PATH="$work/badgrep:$PATH" sh scripts/audit-status.sh 2>/dev/null)
    [ "$(report_section "Markers in code" "$out")" = "src: symbolic link, not searched
tests/b.rs:1:// TODO before a failure
some files not read (find or grep failed)" ]
    expect "markers: a linked root, a marker and a failing grep" 0 $?
    # Both roots as symbolic links: both are named, and "none" is not said.
    rm -rf tests; mkdir -p real2; ln -s real2 tests
    out=$(sh scripts/audit-status.sh 2>/dev/null)
    [ "$(report_section "Markers in code" "$out")" = "src: symbolic link, not searched
tests: symbolic link, not searched" ]
    expect "markers: two linked roots both named" 0 $?
elif pwd -W >/dev/null 2>&1; then
    echo "skipped on Windows: ln -s made no symbolic link"
else
    expect "markers: symbolic link created" 0 1
fi

echo "scripts tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]

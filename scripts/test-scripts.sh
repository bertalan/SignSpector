#!/bin/sh
# Tests for scripts/check-public.sh and scripts/audit-status.sh, run in throw-away git
# repositories. Used by CI (rules job) and runnable by hand: sh scripts/test-scripts.sh
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

# Report-mode tests never call the real gh (network, user account): default gh says "not logged in".
mkdir -p "$work/nogh"; printf '#!/bin/sh\nexit 1\n' > "$work/nogh/gh"; chmod +x "$work/nogh/gh"
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
sh scripts/check-public.sh --range remotes HEAD 2>/dev/null;            expect "old 'remotes' mode refused" 2 $?
# Shallow clones cannot see the history: never a pass.
new_repo
mkdir -p docs; echo a > docs/a.md; git add docs; git commit -qm a
git clone -q --depth 1 "file://$work/r" "$work/shallow" 2>/dev/null
(cd "$work/shallow" && sh scripts/check-public.sh --range "$(git rev-parse HEAD)" HEAD 2>/dev/null); expect "check-public: shallow clone" 2 $?
(cd "$work/shallow" && sh scripts/audit-status.sh --gate-push 2>/dev/null); expect "audit gate: shallow clone" 2 $?
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
sh scripts/audit-status.sh 2>/dev/null | grep -q "HOOKS NOT ENABLED"; expect "no warning with hooks" 1 $?
sh scripts/audit-status.sh 2>/dev/null | grep -q "== Audit cadence"; expect "report ran (hooks enabled)" 0 $?

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
PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null | grep -q "INTERACTION LIMIT EXPIRES"; expect "limit expiring within 30 days" 0 $?
fake_gh "${far}T00:00:00Z"
PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null | grep -q "INTERACTION LIMIT"; expect "limit far away: no warning" 1 $?
PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null | grep -q "== GitHub"; expect "GitHub section ran (limit far away)" 0 $?
fake_gh ""
PATH="$work/ghshim:$PATH" sh scripts/audit-status.sh 2>/dev/null | grep -q "INTERACTION LIMIT NOT ACTIVE"; expect "limit missing" 0 $?

echo "scripts tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]

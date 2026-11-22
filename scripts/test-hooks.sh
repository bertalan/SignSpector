#!/bin/sh
# End-to-end tests of the git hooks: real pushes and commits in throw-away repositories,
# through .githooks/pre-push and .githooks/commit-msg. Run: sh scripts/test-hooks.sh
# (pre-commit runs cargo and is exercised by every real commit; its rule steps are the
# scripts tested in test-scripts.sh.)
# Sensitive-looking data is written with octal escapes (\143 = c) so that this file does
# not match the patterns it tests.
set -u
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

top=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
expect() { # expect <description> <expected exit> <actual exit>
    if [ "$2" -eq "$3" ]; then passed=$((passed + 1)); else
        failed=$((failed + 1)); echo "FAIL: $1 (expected exit $2, got $3)" >&2; fi
}

leak=$(printf 'mario.rossi@gmail.\143om')

# A repository with the real hooks and scripts, two bare remotes, an audit as first commit.
new_repo() {
    rm -rf "$work/r" "$work/origin.git" "$work/usb.git"
    git init -q --bare "$work/origin.git"; git init -q --bare "$work/usb.git"
    mkdir -p "$work/r" && cd "$work/r" || exit 2
    git init -q -b main
    mkdir -p scripts .githooks docs/audits
    cp "$top/scripts/check-public.sh" "$top/scripts/audit-status.sh" scripts/
    cp "$top/.githooks/pre-push" "$top/.githooks/commit-msg" .githooks/
    echo audit > docs/audits/0001.md
    git add -A && git commit -qm initial
    git remote add origin "$work/origin.git"; git remote add usb "$work/usb.git"
    git config core.hooksPath .githooks
    git push -q origin main >/dev/null 2>&1
}
# Commit without hooks (pre-commit would need cargo); the pushes below use the real hooks.
raw_commit() { git -c core.hooksPath=/dev/null commit -q "$@"; }
add_doc() { printf '%s\n' "$2" > "docs/$1.md"; git add docs; raw_commit -m "$1"; }

# --- pre-push ----------------------------------------------------------------------------------
new_repo
add_doc clean "nothing personal"
git push -q origin main >/dev/null 2>&1;               expect "clean push allowed" 0 $?

new_repo
git switch -q -c topic
add_doc leak "$leak"; git rm -q docs/leak.md; raw_commit -m "remove"
git push -q origin topic >/dev/null 2>&1;              expect "new branch: leak added then removed refused" 1 $?

new_repo
add_doc leak "$leak"
git push -q origin main >/dev/null 2>&1;               expect "existing branch: leak refused" 1 $?

# A commit pushed elsewhere first (no hook there) is still checked when it goes to origin.
new_repo
git switch -q -c topic
add_doc leak "$leak"; git rm -q docs/leak.md; raw_commit -m "remove"
git push -q --no-verify usb topic >/dev/null 2>&1
git push -q origin topic >/dev/null 2>&1;              expect "second remote does not hide commits" 1 $?

new_repo
git tag -a v0 -m "release by $leak"
git push -q origin v0 >/dev/null 2>&1;                 expect "annotated tag message scanned" 1 $?

new_repo
git switch -q -c gone; git push -q origin gone >/dev/null 2>&1
git push -q origin --delete gone >/dev/null 2>&1;      expect "branch deletion allowed" 0 $?

new_repo
for i in 1 2 3 4 5 6; do add_doc "c$i" "commit $i"; done
git push -q origin main >/dev/null 2>&1;               expect "past the audit cadence refused" 1 $?

# --- commit-msg --------------------------------------------------------------------------------
new_repo
echo x > docs/x.md; git add docs
git -c core.hooksPath=.githooks commit -q -m "contact $leak" >/dev/null 2>&1; expect "email in message refused" 1 $?
git -c core.hooksPath=.githooks commit -q -m "clean message" >/dev/null 2>&1; expect "clean message allowed" 0 $?
# git commit -v: the diff below the scissors line is not part of the message.
echo y > docs/y.md; git add docs
printf 'Remove a path\n# ------------------------ >8 ------------------------\n-%s\n' "$leak" > "$work/msg"
sh .githooks/commit-msg "$work/msg" >/dev/null 2>&1;  expect "diff below scissors ignored" 0 $?

echo "hooks tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]

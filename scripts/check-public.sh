#!/bin/sh
# The repository is PUBLIC: refuse anything that may carry personal or sensitive data.
#   scripts/check-public.sh --staged        files in the index (pre-commit hook)
#   scripts/check-public.sh --tree REV      every file and the message of a commit (pre-push, CI)
#   scripts/check-public.sh --message FILE  a commit message being written (commit-msg hook)
# Exit 0 clean, 1 content blocked, 2 cannot check (bad revision, git error): never a silent pass.
# A false positive is solved by changing this script in a reviewed commit, never with --no-verify.
set -uf
# Byte-wise matching: binary files (real .p7m) carry names and codici fiscali in clear text.
export LC_ALL=C

cannot() { echo "Error: cannot check: $1" >&2; exit 2; }

tmp=$(mktemp) || cannot "mktemp failed"
trap 'rm -f "$tmp"' EXIT

mode=${1:-}
message=""
case "$mode" in
    --staged)
        files=$(git -c core.quotepath=off diff --cached --name-only --diff-filter=ACMR) || cannot "git diff failed"
        show() { git show ":$1"; } ;;
    --tree)
        rev=${2:-}
        [ -n "$rev" ] || cannot "revision missing"
        git rev-parse --verify --quiet "$rev^{commit}" >/dev/null || cannot "not a commit: $rev"
        files=$(git -c core.quotepath=off ls-tree -r --name-only "$rev") || cannot "git ls-tree failed on $rev"
        message=$(git log -1 --format=%B "$rev") || cannot "git log failed on $rev"
        show() { git show "$rev:$1"; } ;;
    --message)
        [ -r "${2:-}" ] || cannot "message file missing"
        files=""
        message=$(grep -v '^#' "$2") ;;
    *) echo "usage: $0 --staged | --tree REV | --message FILE" >&2; exit 2 ;;
esac

# 1. Allowlist of paths: anything else needs a deliberate change here.
allowed='^(LICENSE|[^/]+\.md|Cargo\.(toml|lock)|(rust-toolchain|clippy|deny|bacon|rustfmt)\.toml'
allowed="$allowed"'|\.git(ignore|attributes)|\.githooks/[a-z-]+|\.cargo/config\.toml|\.config/nextest\.toml'
allowed="$allowed"'|\.github/[A-Za-z0-9_/-]+\.ya?ml|\.claude/agents/[a-z0-9-]+\.md|scripts/[a-z0-9-]+\.sh'
allowed="$allowed"'|src/[A-Za-z0-9_/]+\.rs|tests/[a-z0-9_]+\.rs|tests/fixtures/[A-Za-z0-9_./-]+|docs/(audits/)?[a-z0-9-]+\.md'
allowed="$allowed"'|assets/tsl-it\.xml)$'

# 2. Content that must never appear. [x] brackets keep this file from matching itself.
#    assets/tsl-it.xml is the official public AgID list: exempt.
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
email_ok='@(example\.(com|org|net)|[a-z0-9.-]+\.(test|invalid|example))\b|noreply'
# Windows paths also as written in source strings (double backslashes) or with forward slashes.
local_path='/[U]sers/[^/[:space:]]+|/home/[a-z][^/[:space:]]*|[A-Za-z]:[\\/]+[U]sers[\\/]'
codice_fiscale='\b[A-Z]{6}[0-9LMNPQRSTUV]{2}[A-EHLMPRST][0-9LMNPQRSTUV]{2}[A-Z][0-9LMNPQRSTUV]{3}[A-Z]\b'
secret='BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_[p]at_|sk-[a]nt-|AKIA[0-9A-Z]{16}|xox[bp]-'

fail=0
problem() { echo "  $1: $2" >&2; fail=1; }

# Scans the file $tmp; $1 names it in messages.
scan() {
    content=$(grep -aE "$secret|$local_path|$codice_fiscale|$email" "$tmp") || return 0
    printf '%s\n' "$content" | grep -aEq "$secret" && problem "$1" "private key or token"
    printf '%s\n' "$content" | grep -aEq "$local_path" && problem "$1" "local path with a user name"
    printf '%s\n' "$content" | grep -aEq "$codice_fiscale" && problem "$1" "possible codice fiscale"
    printf '%s\n' "$content" | grep -aEo "$email" | grep -aEvq "$email_ok" && problem "$1" "email address"
    return 0
}

old_ifs=$IFS
IFS='
'
for f in $files; do
    if ! printf '%s\n' "$f" | grep -aEq "$allowed"; then
        problem "$f" "path not allowed in the public repository"
        continue
    fi
    [ "$f" = assets/tsl-it.xml ] && continue
    show "$f" > "$tmp" || cannot "cannot read $f"
    scan "$f"
done
IFS=$old_ifs

if [ -n "$message" ]; then
    printf '%s\n' "$message" > "$tmp"
    scan "commit message"
fi

if [ "$fail" -ne 0 ]; then
    echo "Error: the repository is public, content blocked (see above)." >&2
    exit 1
fi

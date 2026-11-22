#!/bin/sh
# The repository is PUBLIC: refuse anything that may carry personal or sensitive data.
#   scripts/check-public.sh --staged     files in the index (pre-commit hook)
#   scripts/check-public.sh --tree REV   every file of a commit (pre-push hook, manual audit)
# A false positive is solved by changing this script in a reviewed commit, never with --no-verify.
set -uf
# Byte-wise matching: binary files (real .p7m) carry names and codici fiscali in clear text.
export LC_ALL=C

mode=${1:-}
case "$mode" in
    --staged) files=$(git -c core.quotepath=off diff --cached --name-only --diff-filter=ACMR); show() { git show ":$1"; } ;;
    --tree)   rev=${2:?revision missing}; files=$(git -c core.quotepath=off ls-tree -r --name-only "$rev"); show() { git show "$rev:$1"; } ;;
    *) echo "usage: $0 --staged | --tree REV" >&2; exit 2 ;;
esac

# 1. Allowlist of paths: anything else needs a deliberate change here.
allowed='^(LICENSE|[^/]+\.md|Cargo\.(toml|lock)|(rust-toolchain|clippy|deny|bacon|rustfmt)\.toml'
allowed="$allowed"'|\.git(ignore|attributes)|\.githooks/[a-z-]+|\.cargo/config\.toml|\.config/nextest\.toml'
allowed="$allowed"'|\.github/[A-Za-z0-9_/-]+\.ya?ml|\.claude/agents/[a-z0-9-]+\.md|scripts/[a-z0-9-]+\.sh'
allowed="$allowed"'|src/[A-Za-z0-9_/]+\.rs|tests/[a-z0-9_]+\.rs|tests/fixtures/[A-Za-z0-9_./-]+|docs/(audits/)?[a-z0-9-]+\.md'
allowed="$allowed"'|assets/tsl-it\.xml)$'

# 2. Content that must never appear ([x] brackets keep this file from matching itself) (assets/tsl-it.xml is the official public AgID list: exempt).
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
email_ok='@(example\.(com|org|net)|[a-z0-9.-]+\.(test|invalid|example))\b|noreply'
local_path='/[U]sers/[^/[:space:]]+|/home/[a-z][^/[:space:]]*|[A-Za-z]:\\Users\\'
codice_fiscale='\b[A-Z]{6}[0-9LMNPQRSTUV]{2}[A-EHLMPRST][0-9LMNPQRSTUV]{2}[A-Z][0-9LMNPQRSTUV]{3}[A-Z]\b'
secret='BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_[p]at_|sk-[a]nt-|AKIA[0-9A-Z]{16}|xox[bp]-'

fail=0
problem() { echo "  $1: $2" >&2; fail=1; }

old_ifs=$IFS
IFS='
'
for f in $files; do
    if ! printf '%s\n' "$f" | grep -aEq "$allowed"; then
        problem "$f" "path not allowed in the public repository"
        continue
    fi
    [ "$f" = assets/tsl-it.xml ] && continue
    content=$(show "$f" | grep -aE "$secret|$local_path|$codice_fiscale|$email" 2>/dev/null) || true
    [ -z "$content" ] && continue
    printf '%s\n' "$content" | grep -aEq "$secret" && problem "$f" "private key or token"
    printf '%s\n' "$content" | grep -aEq "$local_path" && problem "$f" "local path with a user name"
    printf '%s\n' "$content" | grep -aEq "$codice_fiscale" && problem "$f" "possible codice fiscale"
    printf '%s\n' "$content" | grep -aEo "$email" | grep -aEvq "$email_ok" && problem "$f" "email address"
done
IFS=$old_ifs

if [ "$fail" -ne 0 ]; then
    echo "Error: the repository is public, content blocked (see above)." >&2
    exit 1
fi

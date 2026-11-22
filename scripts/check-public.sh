#!/bin/sh
# The repository is PUBLIC: refuse anything that may carry personal or sensitive data.
#   scripts/check-public.sh --staged          files in the index (pre-commit hook)
#   scripts/check-public.sh --tree REV        files, message and identities of one commit
#   scripts/check-public.sh --range BASE TIP  every commit of a push (pre-push hook, CI):
#       BASE = a commit     commits in BASE..TIP
#       BASE = remotes      commits of TIP not on any remote branch (new branch)
#       BASE = tip          TIP only (scheduled runs)
#     For each commit: the files it adds or changes, its message, author and committer;
#     then the whole tree of TIP.
#   scripts/check-public.sh --message FILE    a commit message being written (commit-msg hook)
# Exit 0 clean, 1 content blocked, 2 cannot check (bad revision, git error): never a silent pass.
# A false positive is solved by changing this script in a reviewed commit, never with --no-verify.
#
# Known limits (not detected): names of people, phone numbers, host names, IP addresses,
# lower-case codici fiscali, text stored as UTF-16 (BMPString). Review remains necessary.
set -uf
# Byte-wise matching: binary files (real .p7m) carry names and codici fiscali in clear text.
export LC_ALL=C

cannot() { echo "Error: cannot check: $1" >&2; exit 2; }

tmp=$(mktemp) || cannot "mktemp failed"
trap 'rm -f "$tmp"' EXIT

# 1. Allowlist of paths: anything else needs a deliberate change here.
allowed='^(LICENSE|(README|CLAUDE|CHANGELOG|CONTRIBUTING|SECURITY)\.md|Cargo\.(toml|lock)|(rust-toolchain|clippy|deny|bacon|rustfmt)\.toml'
allowed="$allowed"'|\.git(ignore|attributes)|\.githooks/[a-z-]+|\.cargo/config\.toml|\.config/nextest\.toml'
allowed="$allowed"'|\.github/[A-Za-z0-9_/-]+\.ya?ml|\.claude/agents/[a-z0-9-]+\.md|scripts/[a-z0-9-]+\.sh'
allowed="$allowed"'|src/[A-Za-z0-9_/]+\.rs|tests/[a-z0-9_]+\.rs|tests/fixtures/[A-Za-z0-9_./-]+|docs/(audits/)?[a-z0-9-]+\.md'
allowed="$allowed"'|assets/tsl-it\.xml)$'
# Key material is never committed, not even test keys (fixtures generate them at test time).
denied='\.(p12|pfx|key|pem)$'

# 2. Content that must never appear. [x] brackets keep this file from matching itself.
#    assets/tsl-it.xml is the official public AgID list: exempt.
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# Whole addresses that may appear: fake test domains and no-reply addresses.
email_ok='^([^@]+@(example\.(com|org|net)|[a-z0-9.-]+\.(test|invalid|example))|noreply@[a-z0-9.-]+|[0-9]+\+[A-Za-z0-9-]+@users\.noreply\.github\.com)$'
# User folders: macOS, Linux, Windows (also as written in source strings, or with forward slashes).
local_path='/[U]sers/[^/[:space:]]+|/home/[A-Za-z][^/[:space:]]*|[A-Za-z]:[\\/]+([U]sers|Documents and Settings)[\\/]'
# No word boundaries: inside DER the next byte is often a tag such as 0x30/0x31 ("0"/"1").
codice_fiscale='[A-Z]{6}[0-9LMNPQRSTUV]{2}[A-EHLMPRST][0-9LMNPQRSTUV]{2}[A-Z][0-9LMNPQRSTUV]{3}[A-Z]'
secret='BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_[p]at_|sk-[a]nt-|AKIA[0-9A-Z]{16}|xox[bp]-'

fail=0
problem() { echo "  $1: $2" >&2; fail=1; }

# Scans the file $tmp; $1 names it in messages.
scan_tmp() {
    content=$(grep -aE "$secret|$local_path|$codice_fiscale|$email" "$tmp") || return 0
    printf '%s\n' "$content" | grep -aEq "$secret" && problem "$1" "private key or token"
    printf '%s\n' "$content" | grep -aEq "$local_path" && problem "$1" "local path with a user name"
    printf '%s\n' "$content" | grep -aEq "$codice_fiscale" && problem "$1" "possible codice fiscale"
    printf '%s\n' "$content" | grep -aEo "$email" | grep -aEvq "$email_ok" && problem "$1" "email address"
    return 0
}

scan_text() { printf '%s\n' "$2" > "$tmp"; scan_tmp "$1"; }

# check_files PREFIX FILES: paths and contents; PREFIX is ":" (index) or "REV:".
check_files() {
    old_ifs=$IFS
    IFS='
'
    for f in $2; do
        if ! printf '%s\n' "$f" | grep -aEq "$allowed"; then
            problem "$f" "path not allowed in the public repository"
            continue
        fi
        if printf '%s\n' "$f" | grep -aEq "$denied"; then
            problem "$f" "key material is never committed"
            continue
        fi
        [ "$f" = assets/tsl-it.xml ] && continue
        git show "$1$f" > "$tmp" || cannot "cannot read $1$f"
        scan_tmp "$f"
    done
    IFS=$old_ifs
    scan_text "file names" "$2"
}

verify_commit() { git rev-parse --verify --quiet "$1^{commit}" >/dev/null || cannot "not a commit: $1"; }

# Message, author and committer of a commit: all published.
check_meta() {
    meta=$(git log -1 --format='%an <%ae>%n%cn <%ce>%n%B' "$1") || cannot "git log failed on $1"
    scan_text "commit $(git rev-parse --short "$1") (identity or message)" "$meta"
}

# Files a commit adds or changes (whole tree for merges).
commit_files() {
    parents=$(git rev-list --parents -n 1 "$1" | wc -w) || cannot "git rev-list failed on $1"
    if [ "$parents" -gt 2 ]; then
        git -c core.quotepath=off ls-tree -r --name-only "$1" || cannot "git ls-tree failed on $1"
    else
        git -c core.quotepath=off diff-tree --root -r --no-commit-id --name-only --diff-filter=ACMRT "$1" \
            || cannot "git diff-tree failed on $1"
    fi
}

tree_files() { git -c core.quotepath=off ls-tree -r --name-only "$1" || cannot "git ls-tree failed on $1"; }

case "${1:-}" in
    --staged)
        files=$(git -c core.quotepath=off diff --cached --name-only --diff-filter=ACMRT) || cannot "git diff failed"
        check_files ":" "$files" ;;
    --tree)
        rev=${2:-}; [ -n "$rev" ] || cannot "revision missing"
        verify_commit "$rev"
        files=$(tree_files "$rev") || exit 2
        check_files "$rev:" "$files"
        check_meta "$rev" ;;
    --range)
        base=${2:-}; tip=${3:-}
        [ -n "$base" ] && [ -n "$tip" ] || cannot "usage: --range BASE TIP"
        verify_commit "$tip"
        case "$base" in
            tip)     commits="" ;;
            remotes) commits=$(git rev-list "$tip" --not --remotes) || cannot "git rev-list failed" ;;
            *)       verify_commit "$base"
                     commits=$(git rev-list "$base..$tip") || cannot "git rev-list failed" ;;
        esac
        n=0
        for c in $commits; do
            files=$(commit_files "$c") || exit 2
            check_files "$c:" "$files"
            check_meta "$c"
            n=$((n + 1))
        done
        files=$(tree_files "$tip") || exit 2
        check_files "$tip:" "$files"
        check_meta "$tip"
        echo "public check: $n commits and the tree of $(git rev-parse --short "$tip") scanned" ;;
    --message)
        [ -r "${2:-}" ] || cannot "message file missing"
        # Comment lines are scanned too: `git commit -m` keeps them in the commit.
        cp "$2" "$tmp" || cannot "cannot read $2"
        scan_tmp "commit message" ;;
    *) echo "usage: $0 --staged | --tree REV | --range BASE TIP | --message FILE" >&2; exit 2 ;;
esac

if [ "$fail" -ne 0 ]; then
    echo "Error: the repository is public, content blocked (see above)." >&2
    exit 1
fi

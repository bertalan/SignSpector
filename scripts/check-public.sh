#!/bin/sh
# The repository is PUBLIC: refuse anything that may carry personal or sensitive data.
#   scripts/check-public.sh --staged          files in the index (pre-commit hook)
#   scripts/check-public.sh --range BASE TIP  every commit of a push (pre-push hook, CI):
#       BASE = a commit     commits in BASE..TIP
#       BASE = remote:NAME  commits of TIP not on any branch of that remote (new branch);
#                           other remotes never hide commits
#       BASE = tip          TIP only (scheduled runs)
#     For each commit: the files it adds or changes, its message, author and committer;
#     then the whole tree of TIP, and the tag message and tagger when TIP is an annotated tag.
#     Shallow clones are refused (exit 2): they cannot see the history.
#   scripts/check-public.sh --message FILE    a commit message being written (commit-msg hook)
# Exit 0 clean, 1 content blocked, 2 cannot check (bad revision, git error): never a silent pass.
# A false positive is solved by changing this script in a reviewed commit, never with --no-verify.
#
# Known limits (not detected): names of people, phone numbers, host names, IP addresses,
# lower-case codici fiscali, text stored as UTF-16 (BMPString) or base64 (base64 envelopes:
# fixtures must be DER), branch names; at commit time, text below a hand-typed copy of
# git's scissors block (pre-push catches it). Review remains necessary.
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
allowed="$allowed"'|src/[A-Za-z0-9_/]+\.rs|tests/[a-z0-9_]+\.rs|tests/fixtures/[A-Za-z0-9_./-]+|docs/(audits/)?[a-z0-9-]+\.md)$'
# Key material is never committed, not even test keys (fixtures generate them at test time).
denied='\.(p12|pfx|key|pem)$'

# 2. Content that must never appear. [x] brackets keep this file from matching itself.
#    Trusted lists are never stored here: the release build downloads them (design R44).
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
    content=$(grep -aE "$secret|$local_path|$codice_fiscale|$email" "$tmp")
    rc=$?
    [ "$rc" -eq 1 ] && return 0          # no match
    [ "$rc" -eq 0 ] || cannot "grep failed on $1"
    known=0                              # did the match fall in a known category?
    if printf '%s\n' "$content" | grep -aEq "$secret"; then problem "$1" "private key or token"; known=1; fi
    if printf '%s\n' "$content" | grep -aEq "$local_path"; then problem "$1" "local path with a user name"; known=1; fi
    if printf '%s\n' "$content" | grep -aEq "$codice_fiscale"; then problem "$1" "possible codice fiscale"; known=1; fi
    if printf '%s\n' "$content" | grep -aEq "$email"; then
        known=1                          # allowed addresses (example.com, noreply) are fine
        printf '%s\n' "$content" | grep -aEo "$email" | grep -aEvq "$email_ok" && problem "$1" "email address"
    fi
    # The combined pattern matched but no category did (e.g. a NUL inside the match): block.
    [ "$known" -eq 1 ] || problem "$1" "unrecognised match, check by hand"
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
    --range)
        base=${2:-}; tip=${3:-}
        [ -n "$base" ] && [ -n "$tip" ] || cannot "usage: --range BASE TIP"
        verify_commit "$tip"
        [ "$(git rev-parse --is-shallow-repository)" = false ] || cannot "shallow clone: fetch the full history"
        case "$base" in
            tip)      commits="" ;;
            remote:*) commits=$(git rev-list "$tip" --not --remotes="${base#remote:}") || cannot "git rev-list failed" ;;
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
        if [ "$(git cat-file -t "$tip")" = tag ]; then
            git cat-file -p "$tip" > "$tmp" || cannot "cannot read tag $tip"
            scan_tmp "tag $tip"
        fi
        echo "public check: $n commits and the tree of $(git rev-parse --short "$tip") scanned" ;;
    --message)
        [ -f "${2:-}" ] && [ -r "$2" ] || cannot "message file missing or not a file"
        # Comment lines are scanned too (`git commit -m` keeps them), but not the diff that
        # `git commit -v` appends: the text is cut at git's scissors block (the scissors line
        # followed by git's warning line). A lone scissors line is not cut. Known limit: a
        # hand-typed copy of the whole block looks the same and is cut here too; pre-push
        # scans the stored message and refuses it (tested in test-hooks.sh).
        awk -v sc='# ------------------------ >8 ------------------------' \
            -v warn='# Do not modify or remove the line above.' '
            held { if ($0 == warn) exit; print sc; held = 0 }
            $0 == sc { held = 1; next }
            { print }' "$2" > "$tmp" \
            || cannot "cannot read $2"
        scan_tmp "commit message" ;;
    *) echo "usage: $0 --staged | --range BASE|remote:NAME|tip TIP | --message FILE" >&2; exit 2 ;;
esac

if [ "$fail" -ne 0 ]; then
    echo "Error: the repository is public, content blocked (see above)." >&2
    exit 1
fi

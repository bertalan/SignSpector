# SignSpector

Finds signed and time-stamped files (`.p7m`, `.p7s`, `.tsd`, `.m7m`) under a folder, verifies
signatures and time stamps (AgID trust list) and writes an HTML report; on request it extracts
the signed documents beside the originals. Runs on Windows, macOS and Linux.

A new project in Rust. It takes the idea of an earlier Windows-only tool by the same author
(`p7m-extract`, in C#, kept outside this repository in `../SignSpector-legacy/`), but it is
**not a port**: requirements and design are in `docs/design.md`, the order of work in `docs/roadmap.md`; read both first. Look at the old
code only when the user asks to.

## Way of working: TDD

1. **Red**: write the test for one small behaviour first; run it and see it fail for the right
   reason.
2. **Green**: the smallest code that makes it pass.
3. **Refactor** with all tests green; `cargo clippy --all-targets -- -D warnings` and
   `cargo fmt` clean.
4. **Independent review**: run the `fable-reviewer` agent (different model) on the cycle's
   changes; fix its findings or explain to the user why not.
5. Commit only when the user asks. The pre-commit hook (`.githooks/`) runs the public-repository
   check, the audit cadence gate, fmt, clippy and tests.

Logic lives in the library (`src/lib.rs` and modules); `src/main.rs` is only the command line.
Unit tests sit beside the code (`#[cfg(test)]`); end-to-end tests of the executable go in
`tests/*.rs` (`assert_cmd`). Tools: `bacon` (tests on every save), `cargo nextest run`,
`cargo llvm-cov nextest` (coverage), `cargo deny check` (licences, advisories, no OpenSSL).

## Coherence audits and unfinished work

Long work across sessions drifts: docs claim things the code does not do, references to
functions or options that never existed, work left half-done. Rules against it:

- **Session start**: run `sh scripts/audit-status.sh` and tell the user what it shows. Unfinished
  work comes first (uncommitted changes, stashes, unpushed commits, unmerged branches, open or
  draft PRs, red CI): finish it, or close it with a written reason, before starting anything new.
- **Branches and PRs** (after the first push): one branch per roadmap step
  (`step/1.1-portable-names`), pushed early as a **draft PR**; marked ready only when CI is
  green and `fable-reviewer` approved; merged into `main` with **rebase** (linear history: every commit counted by the audit cadence stays on `main`), branch deleted. **One step open at
  a time.** A session never ends with a draft PR without a comment saying its state and next
  step; abandoned work is closed with the reason, never left open.
- **Every 3 commits: coherence audit** by the `coherence-auditor` agent (Fable, fresh context,
  read-only): requirements vs tests vs code, every concrete reference checked for existence,
  docs agreeing with each other, unfinished work, project rules, health. Its report is saved as
  `docs/audits/NNNN-YYYY-MM-DD.md` and committed alone (`audit: NNNN`). The hooks enforce the
  cadence: pre-commit refuses a 4th commit without an audit, pre-push refuses to push past it.
- **Findings are verified before acting**: the auditor can be wrong too. Each finding carries
  evidence (`file:line` or command output); check it, then fix it in a normal TDD cycle. When a
  doc and the code disagree on *what the tool should do*, ask the user which one is right;
  never silently align the doc to the code or the code to the doc.
- Also run an audit, outside the cadence, after an interrupted session, a long pause, or when
  something "remembered" cannot be found in the files.

## Public repository: no sensitive data, ever

`github.com/bertalan/SignSpector` is **public**: everything committed is published and stays
in the history even if deleted later. Before every commit and push:

- Never commit: real signed documents or anything extracted from them, names, codici fiscali,
  email addresses, phone numbers, company or office names, local paths that reveal a user name
  (write `~` or `%USERPROFILE%` instead), hostnames, IPs, credentials, tokens, private keys
  (also test keys: fixtures generate them at test time), logs or reports produced on real files.
- Commit messages, issues and PR texts follow the same rules (they are public too).
- Fixtures are synthetic only, with obviously fake identities (`Mario Rossi Test`,
  `example.com`, invalid codici fiscali).
- `scripts/check-public.sh` enforces it: an allowlist of paths (a new kind of file needs a
  deliberate change there) plus a content scan, run by the pre-commit hook on the index and by
  the pre-push hook on every pushed commit. Never bypass it with `--no-verify`; a false
  positive is fixed by changing the script, reviewed like code.
- Before the first push of a session, review the exact file list (`git show --stat`) with the
  user. Pushing is always the user's decision.

## Conventions

- **Language.** Everything in the repository is in English: code, comments, file headers,
  docs, commit messages, script and hook messages, agent prompts and reports. Italian is used
  only when talking to the user (the developer) in the conversation.
- **The tool's own interface is translated** (console messages, `--help`, HTML report, user
  guide): it speaks the operating system's language, or the one chosen by the user
  (`--lang`, see R27 in `docs/design.md`). Source strings are English; every user-facing text
  goes through the translation layer, never hard-coded, and each new text gets its Italian
  translation in the same change.
- Dry run by default: without `extract`/`--apply` nothing is written except the report. The
  same applies to commands that change the system (`install-menu`): without `--apply` they only
  show what they would do.
- Originals are only read, never modified, moved or renamed; existing files are never
  overwritten ("x.pdf" exists with other content -> "x (1).pdf").
- **Never process right after a folder is chosen**: first count and ask for confirmation
  (R28); writing needs a second confirmation on the full write plan, with the number typed
  (R29); no implicit yes without a terminal (R30). Writing only through a `ConfirmedPlan`,
  files created with `create_new`, never outside the chosen folder (R31). File names valid on
  Windows, macOS and Linux at once (R32). Any change here needs the tests of R34.
- **Accessibility is a requirement, not a polish step** (EN 301 549; WCAG 2.2 AA for the
  report; R35–R39). Never convey information by colour or symbols alone; honour `NO_COLOR`,
  `--no-color`, `--plain`; no spinners or rapid line rewriting; no time limits on prompts;
  linear console text, no box drawing; the HTML report is semantic, keyboard operable,
  contrast-checked, works without JavaScript. Every user-facing change keeps its tests green.
- **Uninstall is part of every install feature** (R40–R43): anything that adds something to
  the system records it in the manifest and is removed by `signspector uninstall`, which
  removes only what we installed and never user data.
- Malformed input never panics: it becomes an error for that file. No `unwrap`/`expect`/indexing
  on untrusted data outside tests (enforced by clippy lints in `Cargo.toml`).
- No PowerShell in anything the tool runs on Windows: company PCs force Constrained Language Mode.
- Pure Rust dependencies (no OpenSSL, checked by `cargo deny`): one self-contained executable
  per platform.

## Building

Toolchain: rustup (pinned in `rust-toolchain.toml`) with targets for macOS arm64/x86_64,
Windows (mingw-w64, linker in `.cargo/config.toml`) and Linux musl (`cargo zigbuild`).
Commands in `docs/design.md`. Development happens on the user's Mac; Windows tests on real
files happen on the Windows PC (files move on a USB stick).

## Test data

Real signed documents contain personal data: never commit them, never copy them to the Mac.
They stay on the Windows PC in `tests/corpus/` (git-ignored). Unit tests use synthetic
fixtures only (`tests/fixtures/`).

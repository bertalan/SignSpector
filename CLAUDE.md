# SignSpector

SignSpector finds signed and time-stamped files (`.p7m`, `.p7s`, `.tsd`, `.m7m`) under a folder.
It verifies signatures and time stamps against the European trusted lists and writes an HTML
report. On request it extracts the signed documents beside the originals. It runs on Windows,
macOS and Linux.

It is a new project in Rust. It takes the idea of an earlier Windows-only tool by the same
author (`p7m-extract`, in C#, kept outside this repository in `../SignSpector-legacy/`), but it
is not a port. Requirements and design are in `docs/design.md`, the order of work in
`docs/roadmap.md`: read both first. Look at the old code only when the user asks to.

After cloning, enable the hooks once: `git config core.hooksPath .githooks`.

## How do we write code?

Test first, always. TDD applies to everything that has logic: Rust, shell scripts, git hooks,
the CI workflow. There is no exception for "infrastructure".

1. Red: write the test for one small behaviour first. Run it and see it fail for the right
   reason. For the CI workflow the red is a failing run on GitHub.
2. Green: write the smallest code that makes it pass.
3. Refactor with all tests green; `cargo clippy --all-targets -- -D warnings` and `cargo fmt`
   clean.
4. Proof: every PR description quotes the red output (the failing test run) and the green one.
   Rules that protect (scripts under `scripts/`, safety code) are also checked by breaking each
   rule on a copy and seeing at least one test fail. A rule that no test notices gets a test.
   One exception, decided by the owner: in the "Rust" section of `audit-status.sh`, a breakage
   that shows no bug is listed, not tested. The other known limits of the rule scripts are
   listed in `docs/roadmap.md`, 0.5; the owner marked that step done with them listed.
5. Independent review, by a newly started `fable-reviewer` agent for every review: a different
   model, of equal or higher capability than the author's. Never resume the reviewer. The brief
   holds only:
   - the scope and where the requirements are;
   - the planned commit message, which the reviewer checks as a claim, not a fact;
   - the red and green runs, when no PR exists yet;
   - any owner's decision the changes apply, quoted.

   Never give the reviewer other conclusions of the author or earlier findings. The owner
   decided the brief and these rules on 2026-11-24:
   - The reviewer reviews the uncommitted changes, before the commit. After CHANGES NEEDED, the
     fixed changes get a new review.
   - Commit and push only when the checks are complete. The review must be APPROVED. When a
     coherence audit is due, it runs first, and each of its findings must be closed.
   - A finding of a review or an audit is closed in one of these ways:
     - fixed and reviewed;
     - written into the roadmap step that will fix it;
     - declared wrong by the owner, with the reason in a PR comment;
     - for a point on the message of a commit already pushed, a note in the message of a later
       commit. History is not rewritten.
   - The audit report is committed alone first, without a `fable-reviewer` review. It is pushed
     with the commit that closes its findings, or alone when no commit is needed.
   - Minor rounds have a limit. A round that is APPROVED with only minor points is a minor
     round. The count is of the minor rounds before one commit. A CHANGES NEEDED round in
     between does not restart it; the next commit starts a new count. After the third minor
     round, the minor points left move on. Those of the third round move too. No new round runs
     for them. They move to the next commit of the same PR when the author plans more commits
     in it (owner's decision, 2026-11-24). Otherwise they move to the first commit of the next
     PR. The verdict comment of that round lists them as moved. The commit they move to fixes
     them or writes them into the roadmap step that will fix them. For a point on the message
     of a pushed commit, that commit carries the note.
   - Some points never move: bugs, missing tests, and points on personal data, or on
     confirmation or writing files (R28–R34). They are fixed and reviewed before the commit.
   - The review leaves a trace of what it approved. The reviewer reports the tree of its
     staged copy (`git write-tree`). The verdict comment quotes it, with the subject line of the
     reviewed commit message. After the commit, `git rev-parse HEAD^{tree}` must give the same
     tree. If it does not, nothing is pushed. Undo the commit with `git reset --soft HEAD~1`,
     which keeps the changes, and send them to a new review. The comment that names the commit
     quotes the tree too.

   Post every verdict as a comment on the pull request, as soon as the PR exists: APPROVED or
   CHANGES NEEDED, the findings in short, how each was closed. After the commit, a comment names
   the commit that holds the approved changes. The approval then leaves a trace an audit can
   check; the PR description alone is not enough. The comment is a summary written for the
   public, with repository-relative paths, never the pasted report (reports carry local paths).
   `check-public.sh` does not scan PR comments: save the comment to a file and run
   `sh scripts/check-public.sh --message <file>` before posting.
6. Commit only when the user asks, and only when the checks of step 5 are complete. The hooks
   (`.githooks/`) do this:
   - pre-commit runs the public-repository check, the audit cadence gate, the script tests when
     scripts or hooks change, fmt, clippy and tests;
   - commit-msg scans the message;
   - pre-push scans every commit not yet on the remote it pushes to (other remotes never hide
     commits).

   Script and hook tests: `scripts/test-scripts.sh`, `scripts/test-cleanup.sh`,
   `scripts/test-hooks.sh`.

Logic lives in the library (`src/lib.rs` and modules); `src/main.rs` is only the command line.
Unit tests sit beside the code (`#[cfg(test)]`). End-to-end tests of the executable go in
`tests/*.rs` (`assert_cmd`). Tools: `bacon` (tests on every save), `cargo nextest run`,
`cargo llvm-cov nextest` (coverage), `cargo deny check` (licences, advisories, no OpenSSL).

## How do we keep long work from drifting?

With the six rules below. Long work across sessions drifts: docs claim things the code does not
do, references point to functions or options that never existed, work is left half-done.

- Session start: run `sh scripts/audit-status.sh` and tell the user what it shows. Unfinished
  work comes first: uncommitted changes, stashes, unpushed commits, unmerged branches, open or
  draft PRs, red CI. Finish it, or close it with a written reason, before starting anything new.
- Branches and PRs (after the first push): one branch per roadmap step
  (`step/1.1-portable-names`), pushed early as a draft PR. Mark it ready only when CI is green
  on all four jobs (read in the job list, never assumed from a pending run) and `fable-reviewer`
  approved, with its verdict posted on the PR. Merge it into `main` locally by fast-forward:
  `git switch main && git merge --ff-only step/x && git push`. The merged commits are the same
  ones CI checked, history stays linear and the pre-push hook runs. The GitHub merge button is
  not used: it rewrites commits. One step is open at a time. A session never ends with a draft
  PR without a comment saying its state and next step. Abandoned work is closed with the reason,
  never left open.
- Every 5 commits, a coherence audit by the `coherence-auditor` agent (Fable, a different model
  of equal or higher capability than the author's, fresh context, read-only). It checks
  requirements, tests and code against each other, the existence of every concrete reference,
  the docs against each other, unfinished work, project rules and health. Its report is saved as
  `docs/audits/NNNN-YYYY-MM-DD.md` and committed alone (`audit: NNNN`). The hooks enforce the
  cadence: pre-commit refuses a 6th commit without an audit, pre-push refuses to push past it.
  The gate is a reminder, not a proof: any added report satisfies it. Checking the report's
  findings is what counts.
- Findings are verified before acting, because the auditor can be wrong too. Each finding
  carries evidence (`file:line` or command output). Check it, then fix it in a normal TDD cycle.
  When a doc and the code disagree on what the tool should do, ask the user which one is right.
  Never silently align the doc to the code or the code to the doc.
- After every audit, remove leftovers. `sh scripts/cleanup.sh` removes the local ones without
  asking and says what it removed: `.DS_Store`, `*.orig`, `*.rej` anywhere outside ignored
  folders (also inside untracked ones), and local branches already merged into main. `--plan`
  only lists them. The main session runs the removing form after an audit; agents (auditor,
  reviewer) run only `sh scripts/cleanup.sh --plan`.
  - Worktrees, backups (`*.bak`), editor files and other untracked files are only listed.
  - Agents that work in parallel each get a git worktree under `.claude/worktrees/` (ignored by
    git). They never commit there; the main session takes their changes as a patch. When the
    changes are committed, the main session removes the worktree and its branch, locally.
    First it compares `git -C <worktree> diff HEAD` and
    `git -C <worktree> status --porcelain --untracked-files=all` with the patch it took: a change
    made after the patch is taken again or reported, never lost. Then
    `git worktree remove --force` and `git branch -D`. `--force` is needed because the worktree
    still has uncommitted files.
  - Ignored folders are never touched. `tests/corpus/`, `tests/out/` and `target/` are protected
    even if `.gitignore` lacks them.
  - Deletion happens only locally, from the development environment, never on GitHub. Merged
    remote branches stay there as history. Stale or draft PRs found on GitHub are reported to
    the user.
  - Untracked files that are not recognisable junk are listed for the user, never deleted
    silently.
- Also run an audit outside the cadence: after an interrupted session, after a long pause, or
  when something "remembered" cannot be found in the files.

## What may never reach the public repository?

Anything that could carry personal or sensitive data. `github.com/bertalan/SignSpector` is
public: everything committed is published, and it stays in the history even if deleted later.
Before every commit and push:

- Never commit real signed documents or anything extracted from them. Never commit names, codici
  fiscali, email addresses, phone numbers, company or office names, hostnames, IPs, credentials,
  tokens or private keys (also test keys: fixtures generate them at test time). Never commit
  local paths that reveal a user name (write `~` or `%USERPROFILE%` instead), nor logs or
  reports produced on real files.
- Commit messages, issues and PR texts follow the same rules: they are public too.
- Fixtures are synthetic only, with obviously fake identities (`Mario Rossi Test`,
  `example.com`, invalid codici fiscali).
- `scripts/check-public.sh` enforces part of it. It has an allowlist of paths: a new kind of
  file needs a deliberate change there, and PR texts, notes and key files are not allowed. It
  also scans the content of files, file names, commit messages and identities. The pre-commit,
  commit-msg and pre-push hooks run it. Never bypass them with `--no-verify`. A false positive
  is fixed by changing the script, reviewed like code. The script does not detect names of
  people, phone numbers, host names or IPs: those need review.
- GitHub settings were set on 2026-11-22. They change only with the user's explicit
  authorisation.
  - `main` is protected: the four CI jobs green on an up-to-date commit, also for admins; linear
    history; no force-push, no deletion. No PR is required: merges are local fast-forwards.
  - Merge commits and squash are disabled. There is no automatic branch deletion.
  - Only collaborators may open PRs, issues and comments. This interaction limit lasts 6 months
    at most; the session report warns 30 days before it expires.
  - Fork PR workflows always need approval.
  - Only GitHub-owned actions plus `Swatinem/rust-cache`, `taiki-e/install-action` and
    `EmbarkStudios/cargo-deny-action` are allowed, pinned by SHA.
  - Wiki and projects are off. Vulnerability alerts are on, with no Dependabot PRs. Secret
    scanning with push protection is on.
  - The GitGuardian app installed on the owner's account adds its own secret check to every PR.
    It is not a required check.
- Accepted exception: the repository's first commit (`cd3620d`, "Initial commit", made on the
  GitHub website) has the owner's personal address as author. The owner accepted it on
  2026-11-22; history is not rewritten. Every later commit uses the GitHub no-reply address.
- The hooks are the barrier; CI is only an alarm. When CI runs, the push is already public. A
  pull request also runs its own version of the workflow, so changes to `.github/`, `scripts/`
  and `.githooks/` get a careful review.
- Before the first push of a session, review the exact file list (`git show --stat`) with the
  user. Pushing is always the user's decision.

## Which rules hold everywhere?

These rules hold in every change. They cover texts and language, confirmation and writing
files, accessibility, uninstall, malformed input, PowerShell and dependencies.

- Every text follows `docs/writing.md`: docs, comments, commit messages, PR texts, agent
  prompts, the tool's strings. Texts answer the reader's questions, answer first, in short
  sentences, with code and commands verbatim.
- Everything in the repository is in English: code, comments, file headers, docs, commit
  messages, script and hook messages, agent prompts and reports. Italian is used only when
  talking to the user (the developer) in the conversation.
- The tool's own interface is translated: console messages, `--help`, the HTML report, the user
  guide. It speaks the operating system's language, or the one chosen by the user (`--lang`, R27
  in `docs/design.md`). Source strings are English. Every user-facing text goes through the
  translation layer, never hard-coded, and each new text gets its Italian translation in the
  same change.
- `check` writes no document: only the report (HTML and JSON) and the tool's cache of trusted
  lists and CRLs (R16). Documents come only from an extraction confirmed through R29: `extract`,
  or the interactive end of a `check` run (R20). There is no `--apply`, `--yes` or `--expect`.
- Every command that changes files or the system shows the exact plan first. The one exception
  is `check` in an ordinary run from a script, which writes its report and the cache without a
  question (R16, R30).
- The number is typed only for files found in a folder: files to process in a risky run (R28),
  documents to write (R29). `undo`, menus and `uninstall` ask a yes/no question, default No,
  with answers in words (R30, R35). From the context menu the same confirmations come in a
  native dialog, focus on Cancel. From a script they refuse (R30). `--plan` shows the plan and
  stops.
- The confirmation rules are for the tool. The developer script `scripts/cleanup.sh` is the one
  exception: it removes only junk and merged branches, without asking (see above). Never ask the
  developer to type numbers in chat: the typed count is a rule of the tool, not of the
  conversation.
- Originals are only read, never modified, moved or renamed. Existing files are never
  overwritten: if "x.pdf" exists with other content, the new file is "x (1).pdf".
- Never process right after a person chooses a folder. First count and ask for confirmation
  (R28). From a script an ordinary run is analysed without a question, and a risky one is
  refused. Writing needs a second confirmation on the full write plan, with the number typed
  (R29). There is no implicit yes, ever (R30: terminal, dialog from the context menu, refusal in
  scripts).
- How every file is written, and the only files ever replaced, is R31 in `docs/design.md`: read
  it before touching any write path. File names are valid on Windows, macOS and Linux at once
  (R32). Any change to counting, confirmation, write paths or file names, or to anything else
  R34 covers, needs the tests R34 lists.
- Accessibility is a requirement, not a polish step (EN 301 549; WCAG 2.2 AA for the report;
  R35–R39). Never convey information by colour or symbols alone. Honour `NO_COLOR`, `--no-color`
  and `--plain`. No spinners or rapid line rewriting, no time limits on prompts. Console text is
  linear, with no box drawing. The HTML report is semantic, keyboard operable and
  contrast-checked, and works without JavaScript. Every user-facing change keeps its tests
  green.
- Uninstall is part of every install feature (R40–R43). Anything that adds something to the
  system records it in the manifest and is removed by `signspector uninstall`. That command
  removes only what we installed, never user data.
- Malformed input never panics: it becomes an error for that file. No `unwrap`, `expect` or
  indexing on untrusted data outside tests (enforced by clippy lints in `Cargo.toml`).
- No PowerShell in anything the tool runs on Windows: company PCs force Constrained Language
  Mode.
- Pure Rust dependencies, no OpenSSL (checked by `cargo deny`): one self-contained executable
  per platform.

## How do we build it?

The toolchain is rustup, pinned in `rust-toolchain.toml`. Targets: macOS arm64 and x86_64,
Windows (mingw-w64, linker in `.cargo/config.toml`) and Linux musl (`cargo zigbuild`). The
commands are in `docs/design.md`. Development happens on the user's Mac. Windows tests on real
files happen on the Windows PC, where `tests/corpus/` lives.

## Which test data may we use?

Real signed documents contain personal data. Never commit them, never copy them to the Mac. They
stay on the Windows PC in `tests/corpus/` (git-ignored). Unit tests use synthetic fixtures only
(`tests/fixtures/`).

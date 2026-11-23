# SignSpector: roadmap

Order of work. Requirements (R…) are in `design.md`. Every step is TDD (red -> green ->
refactor), reviewed by the `fable-reviewer` agent, then committed. A step is done when its tests
are green on all three systems in CI and its PR is merged. Mark a step done here (`[x]`) in
the same PR that completes it; the coherence audit checks that the mark is true.

The order follows two ideas:
1. **Safety first**: the parts that decide what gets written (names, collisions, confirmation)
   come before the parts that read envelopes, and are pure functions, easy to test exhaustively.
2. **A thin end-to-end slice early**: as soon as envelopes can be opened, the whole path
   count -> confirm -> plan -> confirm -> write -> report -> undo works on simple files,
   before the long verification work. Problems in the flow show up early.

## Phase 0: groundwork
- [x] 0.1 First commit and push to `main` (after review of the file list). From then on: one
  branch and one draft PR per step, coherence audit every 5 commits, merge by local fast-forward
  (`CLAUDE.md`).
- [x] 0.2 GitHub Actions CI (`.github/workflows/ci.yml`) on Windows, macOS, Linux, on the
  shipped targets (windows-gnu, linux-musl, macOS arm64 + x86_64 build): fmt, clippy, nextest,
  doctests, release build, cargo deny (also weekly), tests of the rule scripts on all three
  systems; public-repository scan of every new commit (`check-public.sh --range`); audit
  cadence on the PR head. Branch protection on `main`: all jobs green, linear history, no
  force-push. CI is an alarm; the local hooks are the barrier.
- [x] 0.2.1 Confirmation rules simplified: the typed number only for files found in a folder
  (R28, R29); `undo`, menus and `uninstall` ask yes/no; from the context menu the same
  confirmations come in a native dialog; from a script nothing that changes anything runs except
  `check` in an ordinary run, which writes its report and the cache (R30);
  `check`/`extract` take several folders (a row each, the total typed); revocation without a
  query per signature (R49); no `--yes`/`--expect`; `scripts/cleanup.sh` removes its safe
  leftovers without asking.
- [ ] 0.3 Fixture generator `scripts/make-fixtures.sh` (Homebrew `openssl@3`): test CA, signers,
  simple `.p7m`/`.p7s`, `.tsd`. Synthetic identities only, private keys never committed
  (generated at test time or kept in `target/`).

- [ ] 0.4 Writing guide (`docs/writing.md`): texts as answers to the reader's questions, no
  machine-made patterns (after Wikipedia's "Signs of AI writing"), answer first, short
  sentences, code and commands verbatim. Rewrite README, design, roadmap, CLAUDE.md and the
  agent prompts with it; comment in `rust-toolchain.toml` (targets and R25, how to update the
  pinned version); session report line when a newer stable Rust exists. The reviews of this
  step also led to owner's decisions on requirements (2026-11-23), recorded in
  `docs/design.md`:
  - what `check` writes (R16);
  - risky runs counted on files of any kind (R28);
  - reports never replaced, and the second report (R16, R20, R31, R33);
  - `--plan` writes and downloads nothing (R19);
  - the cache (R47);
  - no saved preference (R27);
  - `--no-report` (R14, R16);
  - foreign menu items (R41).

  The questions they opened are listed in "What is still open?" in `docs/design.md`, each with
  the roadmap step that needs the answer (1.4, 1.5, 1.6, 1.7, 3.1, 3.2, 3.5, 3.6, 3.7, 3.9, 4.2,
  4.4, 5.1, 5.2, 5.3).
- [ ] 0.5 Remaining gaps in the rule-script tests, found by the reviews of PR #1, PR #2 and
  PR #3 and accepted as known limits for now (each needs a test before the code changes):
  - `check-public.sh`: failures of `git show`, `ls-tree`, `diff-tree` are not each tested;
    names of people, phone numbers, IPs, base64 content and branch names are not detected
    (header "Known limits");
  - `cleanup.sh`: on Windows 5 checks are skipped (names with `\` cannot exist there, and a
    read-only folder does not stop `rm`), so those rules are tested on macOS and Linux only; on
    Windows the double-quote check runs but does not exercise git's quoting; the numbers passed
    to `skip` are written by hand; the GitHub section duplicates `audit-status.sh`; "never asks"
    is checked on the script's text (a word list) and with input on a pipe, never at a real
    terminal; the check "still merged into main" (with full ref names) just before a branch is
    deleted has no test (it guards a race);
  - `audit-status.sh`: in the unfinished-work section, uncommitted changes, stashes and the
    unpushed / not pulled counts have no test (the "AUDIT DUE" and "RED CHECKS" lines, the
    current branch name, unmerged local and remote branches, a missing `main` or `origin/main`,
    the `origin/HEAD` filter and "no tags or other refs" do); the "RED CHECKS" test covers the
    printed line and its absence, not which checks are selected as red (the `gh` stub returns
    the formatted line); only `FAILURE` counts as red today, not cancelled or timed-out jobs nor
    commit statuses: decide and test; the negative RED CHECKS case does not assert that the
    GitHub section ran, and its stub has a dead first line;
  - report-mode tests pass if the script prints nothing in that section.
  - `audit-status.sh`, "Rust" section: five review rounds on PR #3. The reviews of 2557e7f and
    1ac9d1d found minor bugs. All but one were fixed in 1ac9d1d and c3f070e; the missing time
    limit on `rustup check` is the one left (below). The reviews of c3f070e,
    1363b18 and fb41029 found no bug, only breakages no test noticed. The owner decided
    (2026-11-23) to stop the rounds there. A breakage of this section that shows no bug
    is listed on the PR and here, not closed with another round. Known limit: `rustup check`
    has no time limit. It runs only in report mode, after the hook gates, so no commit or push
    waits on it. These three rules are correct today; breaking them on a copy leaves all tests
    green (review of 40e2d4c):
    - unescaping the first dot of the x.y.z check (`1x100.0` would then pass);
    - accepting only a single digit for the major and patch numbers (`10.0.0` would then be
      "not x.y.z");
    - letting the captured rustup version start with a dot.
  - from the targeted review of the third-round fixes:
    - the first push to a new remote scans the whole history and stops on the accepted
      exception `cd3620d` (CLAUDE.md): encode the exception if a second remote is ever added;
    - nested annotated tags: only the outer message is scanned;
    - `core.commentChar` other than `#`: `git commit -v` is refused (fails closed);
    - untested: `cleanup.sh` `--no-merged` with a detached HEAD at an unmerged commit; a
      refused push and a crashing hook both exit 1.
## Phase 1: safe writing core (no cryptography)
- [x] 1.0 **R1a envelope names** (`is_envelope`): delivered with the project setup (0.1).
- [ ] 1.1 **R32 portable names** (`names` module). `portable_name(raw) -> PortableName { name,
  changed }`. Tests, one per rule: forbidden characters, control characters, trailing dot and
  space, reserved Windows names (any case, with extension, superscript digits), leading `-`
  and `.`, `.`/`..`, invalid UTF-8, NFC, 255-byte/255-unit limit without breaking a character
  or the extension, empty result -> fallback name. Property tests (`proptest`): output always
  valid on all three systems, idempotent (`portable(portable(x)) == portable(x)`).
- [ ] 1.2 **Collision key and free name** (R17, R32): `collision_key` (case- and
  normalization-insensitive); `next_free_name("x.pdf", taken)` -> `x (1).pdf`, `x (2).pdf`...,
  still within the length limit.
- [ ] 1.3 **Output name from envelope name** (R16, R18 without content sniffing for now):
  `Relazione.pdf.p7m` -> `Relazione.pdf`, nested `.pdf.p7m.tsd`, uppercase extensions.
- [ ] 1.4 **i18n skeleton** (R27): pick the mechanism (Fluent vs `rust-i18n`, decided with the
  user), English + Italian, `--lang`, OS language detection. Needed before any message below.
  First decide the questions "Before 1.4" in `docs/design.md`.
- [ ] 1.5 **Walk and count** (first decide the questions "Before 1.5" in `docs/design.md`)
  (R1b, R2, R19, R28): one or more folders, a row per folder and the total; regular files only,
  symbolic links met during the walk not followed (a selected one is resolved) and hidden folders
  skipped (both listed in the report), unreadable folders listed; two counts (files to process,
  files of any kind), total size, subfolders. Detection of sensitive folders (drive roots, home,
  Desktop, Documents, system folders, network share roots) and of a risky run (a sensitive
  folder, or more than 10,000 files of any kind over all the folders, subfolders included).
- [ ] 1.6 **Confirmation logic** (R28–R30; first decide the question "Before 1.6" in
  `docs/design.md`): pure functions turning (counts, folder, terminal, dialog via `--interactive`,
  or script; `--plan`) into the question to ask and parsing the answer: typed count (R28 risky run,
  R29), yes/no default No (R30). Typestate `ConfirmedPlan`. Tests at the terminal: Enter, `n`, wrong
  number. Tests from a script: `extract`, `undo`, `install-menu`, `uninstall-menu`, `uninstall`, and
  `check` and `extract --plan` in a risky run, are refused; `check` in an ordinary run runs without
  a question; `check --plan` in any run, `extract --plan` in an ordinary run and the item lists of
  `--plan` run. Also: symbolic links resolved before each folder is judged (all kinds of sensitive
  folder, not only shares); several folders (total, overlaps counted once). The dialogs themselves
  come with the menus (5.2).
- [ ] 1.7 **Safe writer** (R31): `create_new`, next free name on race, removal of partial files,
  stays inside the folder (`..`, symbolic links), free-space check, re-check of originals. First
  decide the questions "Before 1.7" in `docs/design.md`. Folder snapshot test helper (R34)
  introduced here and used from now on.

## Phase 2: opening envelopes (thin slice)
- [ ] 2.1 `ber` reader: definite and indefinite lengths, limits on depth and size, checked
  arithmetic; fuzz target.
- [ ] 2.2 `cms` SignedData parsing: encapsulated content, certificates, signer infos (no
  verification yet); base64 envelopes; nested layers (R3, R4, R7).
- [ ] 2.3 End-to-end slice: `check` and `extract` on simple fixtures through the real flow,
  minimal console output with `--plain`, `--no-color` (R35), minimal JSON (R15), written
  documents recorded in the report with SHA-256, and `undo` (R33).

## Phase 3: verification
- [ ] 3.1 `crypto`: digests, RSA PKCS#1 v1.5, RSA-PSS, ECDSA P-256/P-384/P-521 (R8). First decide
  the question "Before 3.1" in `docs/design.md`.
- [ ] 3.2 `x509`: certificate fields, key usage, qualified/QSCD statements, validity (R9).
  First decide the question "Before 3.2" in `docs/design.md`.
- [ ] 3.3 `xmldsig`: exclusive C14N and XML signature verification (R44), test first,
  fuzzed like `ber`.
- [ ] 3.4 `tsl`: LOTL and national lists, signatures verified, embedded LOTL + Italian list,
  service history (R44, R48).
- [ ] 3.5 Choice of lists from the certifiers' countries, download, cache, `--trust-lists`,
  `--offline` (R45–R47). First decide the questions "Before 3.5" in `docs/design.md`.
- [ ] 3.6 Chain building against the TSL and the system store (R10). First decide the questions
  "Before 3.6" in `docs/design.md`.
- [ ] 3.7 Countersignatures (R11); `tsp`: RFC 3161, `.tsd`, `.m7m` (R5, R12); detached `.p7s` (R6).
  A time stamp is a proved time (R9) only if it verifies per R12 (chain to a trusted-list
  TSA); negative test: a forged or untrusted time stamp changes no verdict. First decide the
  question "Before 3.7" in `docs/design.md`.
- [ ] 3.8 Content sniffing for names without a usable extension (R18).
- [ ] 3.9 Revocation (R49): decide the questions "Before 3.9" in `docs/design.md`; data embedded
  in the signature, CRL per CA with cache, one check per certificate, "revocation not checked"
  offline. Negative tests: revoked before and after the time stamp, revoked with no time stamp
  (cannot be determined, never invalid), stale or forged embedded data, forged or oversized CRL,
  CRL older than the reference time, expired certificate no longer listed, distribution point
  outside `http`/`https`. Also: an embedded CRL older than the reference time when the CA's CRL
  cannot be fetched ("revocation not checked").

## Phase 4: output
- [ ] 4.1 Console summary, colours with contrast, exit codes (R13, R35).
- [ ] 4.2 Accessible HTML report, WCAG 2.2 AA (R14, R36), checker in CI (R39). First decide the
  questions "Before 4.2" in `docs/design.md`.
- [ ] 4.3 Full `--json` (R15); parallel processing with stable output order (R23).
- [ ] 4.4 Command line and translated help, interactive end of run (R19, R20, R37). First decide
  `--open`, `--threads`, `extract --no-report` and double-click detection (questions
  "Before 4.4" in `docs/design.md`).

## Phase 5: system integration
- [ ] 5.1 Install manifest (R41). First decide how `create_new` applies to registry keys and
  `.workflow` folders and the other questions "Before 5.1" in `docs/design.md`.
- [ ] 5.2 Context menu per OS (R21, R38) with the confirmation dialogs (R30): first decide the
  questions "Before 5.2" in `docs/design.md` (Enter in a number field, what the shorter dialog
  summary must show), with R34 tests; Windows "Installed apps" entry (R42).
- [ ] 5.3 `uninstall` (R40–R43). First decide what happens to a file in the cache folder that
  the tool did not write (questions "Before 5.3" in `docs/design.md`).

## Phase 6: release
- [ ] 6.1 Builds for all targets; `.deb`, `.rpm`, `.tar.gz` (R24, R25); one self-contained
  executable per platform, pure Rust (R22, enforced by `cargo deny`); version tag (R26).
- [ ] 6.2 Test on the company Windows PC (antivirus, SmartScreen, AppLocker) with the real corpus.
- [ ] 6.3 Manual accessibility checks, `docs/accessibility.md` (R39); user guide (R37).
- [ ] 6.4 `1.0.0` when ready to replace the old tool.

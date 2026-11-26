# SignSpector: roadmap

## How does a step get done?

Each step is test-driven: red, green, refactor. A new `fable-reviewer` agent reviews the changes
of each commit before they are committed; the audit report is the one exception (`CLAUDE.md`). A
step is done when the review of its last changes is APPROVED and CI is green on all four jobs on
its last commit. Only then is its PR merged (owner's decision, 2026-11-24). Each step writes the
tests of R34 for the commands and modules it introduces, as soon as they can be tested. R34 is
the only list of these tests; the review of each step checks the step against it (owner's
decision, 2026-11-24). Mark the step done here (`[x]`) in the PR that completes it; the
coherence audit checks that the mark is true. Requirements (R…) are in `docs/design.md`.

## Why this order?

Two ideas set it:

1. Safety first. The parts that decide what gets written (names, collisions, confirmation) come
   before the parts that read envelopes. They are pure functions, easy to test exhaustively.
2. A thin end-to-end slice early. As soon as envelopes can be opened, the whole path works on
   simple files: count, confirm, plan, confirm, write, report, undo. This comes before the long
   verification work, so problems in the flow show up early.

## Phase 0: what must be in place before the code?

The repository, CI, the writing guide and the fixture generator. Then a list of the known gaps
in the script tests, and the changes to the way of working adopted on 2026-11-25.

- [x] 0.1 First commit and push to `main`, after a review of the file list. From then on: one
  branch and one draft PR per step, a coherence audit every 5 commits, merges by local
  fast-forward (`CLAUDE.md`).
- [x] 0.2 GitHub Actions CI (`.github/workflows/ci.yml`) on Windows, macOS and Linux, on the
  shipped targets (windows-gnu, linux-musl, macOS arm64 + x86_64 build). It runs fmt, clippy,
  nextest, doctests, the release build, cargo deny (also weekly) and the tests of the rule
  scripts on all three systems. It scans every new commit for the public repository
  (`check-public.sh --range`) and checks the audit cadence on the PR head. Branch protection on
  `main`: all jobs green, linear history, no force-push. CI is an alarm; the local hooks are the
  barrier.
- [x] 0.2.1 Confirmation rules simplified:
  - the number is typed only for files found in a folder (R28, R29);
  - `undo`, menus and `uninstall` ask yes/no;
  - from the context menu the same confirmations come in a native dialog;
  - from a script nothing that changes anything runs, except `check` in an ordinary run, which
    writes its report and the cache (R30);
  - `check` and `extract` take several folders (a row each, the total typed);
  - revocation without a query per signature (R49);
  - no `--yes` or `--expect`;
  - `scripts/cleanup.sh` removes its safe leftovers without asking.
- [ ] 0.3 Fixture generator `scripts/make-fixtures.sh` (Homebrew `openssl@3`): test CA, signers,
  simple `.p7m`/`.p7s`, `.tsd`. Synthetic identities only. Private keys are never committed:
  they are generated at test time or kept in `target/`.
- [x] 0.4 Writing guide (`docs/writing.md`). Texts answer the reader's questions, with the
  answer first and short sentences. Code and commands stay verbatim. Texts use no machine-made
  patterns (after Wikipedia's "Signs of AI writing"). Rewrite README, design, roadmap,
  `CLAUDE.md` and the agent prompts with it. Also in this step:
  - a comment in `rust-toolchain.toml`: targets and R25, how to update the pinned version;
  - a "Rust" section in the session report (`scripts/audit-status.sh`) that names a newer stable
    Rust when one exists;
  - owner's decisions on requirements, recorded in `docs/design.md`. Those without a date were
    taken in the reviews of this step, on 2026-11-23. Later ones carry their date:
    - what `check` writes (R16);
    - risky runs counted on files of any kind (R28);
    - reports never replaced, and the second report (R16, R20, R31, R33);
    - `--plan` writes and downloads nothing (R19);
    - at the terminal, any answer other than the right number never confirms (R30);
    - the cache (R47);
    - no saved preference (R27);
    - `--no-report` (R14, R16);
    - foreign menu items (R41);
    - R34 also tests each kind of sensitive folder selected directly (R28), decided on
      2026-11-24;
    - signatures inside a signed PDF are found and reported as not verified (R50), decided on
      2026-11-25. Their verification was decided on 2026-11-25 too, and its version, `2.0.0`,
      on 2026-11-26. Also on 2026-11-26 the owner decided which ones `2.0.0` verifies: the
      sub-filters `ETSI.CAdES.detached`, `adbe.pkcs7.detached` and `adbe.pkcs7.sha1`;
    - other signed formats and cases are evaluated for version `2.0.0`, decided on 2026-11-25
      and 2026-11-26. Signed PDF files on their own joined the list on 2026-11-26. The same day
      `adbe.pkcs7.detached` and `adbe.pkcs7.sha1` left it; only `adbe.x509.rsa_sha1` stays. The
      list is in `docs/design.md`, "What do we evaluate for version 2?".

  The questions these decisions opened are in "What is still open?" in `docs/design.md`. Each
  names the roadmap step that needs the answer: 1.4, 1.5, 1.6, 1.7, 2.4, 3.1, 3.2, 3.5, 3.6,
  3.7, 3.9, 4.2, 4.4, 5.1, 5.2, 5.3, 7.1.
- [x] 0.5 Remaining gaps in the rule-script tests. The reviews of PR #1, PR #2 and PR #3 found
  them. This step closed the ones below that are not listed as known limits. The owner marked
  the step done with these limits listed (2026-11-25). Each known limit needs a test before the
  code it names changes, except in the "Rust" section (below).
  - Closed in this step, test first:
    - `check-public.sh`: a failing `git show`, `ls-tree`, `diff-tree`, `cat-file`, `log`,
      `rev-list` or `diff` stops the check with exit 2. Two of them passed in silence before:
      `rev-list --parents` on a merge commit and `cat-file -t` on a tag. Nested annotated tags
      are scanned to the innermost one;
    - hooks: a check that finds a problem, is missing or cannot run makes every hook refuse;
    - `cleanup.sh`: the "still merged into main" check just before deletion, a branch created
      at `main` (audit 0003, F6), a detached HEAD at an unmerged commit, checked skip counts;
    - `audit-status.sh`, what counts as red: everything that is not green, and only the latest
      attempt of each check (owner's decisions, 2026-11-24 and 2026-11-25). NEUTRAL and SKIPPED
      are green, as in GitHub's branch protection: the report flags what would block a merge;
    - `audit-status.sh`, other tests: uncommitted changes, stashes and the unpushed and
      not-pulled counts now have tests. A test that checks a line is absent now fails when its
      section prints nothing, except in the "Rust" section (below);
    - `audit-status.sh`, failures said: a failing `gh` call prints "not read" for open pull
      requests, their checks, the CI runs and the interaction limit. `core.hooksPath` may be the
      absolute path of this repository's `.githooks`, in POSIX or drive-letter form.
  - Known limits of `check-public.sh`: the list is in the header of the script, "Known limits"
    (for example names of people, phone numbers and IPs are not detected).
  - Known limits of `cleanup.sh`:
    - on Windows 5 checks are skipped: names with `\` cannot exist there, and a read-only folder
      does not stop `rm`. Those rules are tested on macOS and Linux only;
    - on Windows the double-quote check runs but does not exercise git's quoting;
    - the GitHub section duplicates `audit-status.sh`;
    - "never asks" is checked on the script's text (a word list) and with input on a pipe, never
      at a real terminal;
    - nothing checks that every `off_windows` block ends with `end_off_windows`;
    - a commit that only a detached HEAD holds is not mentioned in any report. Nothing removes
      it.
  - Known limits of `audit-status.sh`:
    - the `jq` projection inside the `gh` call is not tested: the stub returns its output;
    - `gh` gives no event for a check. Two runs of the same workflow and job on one head count
      as one check. Example: a green manual `workflow_dispatch` run hides a failed
      `pull_request` run;
    - start times are compared as strings, which holds for GitHub's whole-second times;
    - a check name with a backslash is printed with the backslash doubled (`@tsv` escapes it);
    - `gh pr list` reads at most 30 open pull requests, its default;
    - the exit status of the `awk` that selects the red checks is not checked;
    - "Rust" section: the owner decided (2026-11-23) that a breakage of this section that shows
      no bug is listed here, not tested. These are listed:
      - `rustup check` has no time limit. It runs only in report mode, after the hook gates;
      - its negative tests pass on a section that prints nothing;
      - three rules are correct today, but breaking them on a copy leaves all tests green
        (review of 40e2d4c):
        - unescaping the first dot of the x.y.z check (`1x100.0` would then pass);
        - accepting only a single digit for the major and patch numbers (`10.0.0` would then
          be "not x.y.z");
        - letting the captured rustup version start with a dot.
  - Known limits of the hooks:
    - the first push to a new remote scans the whole history and stops on the accepted exception
      `cd3620d` (`CLAUDE.md`). Encode the exception if a second remote is ever added;
    - `core.commentChar` other than `#`: `git commit -v` is refused (fails closed).

- [ ] 0.6 Way of working: the four changes the owner adopted on 2026-11-25, after one point
  closed first.
  - Closed first, test first: the marker search of `audit-status.sh` says when `find` or `grep`
    fails, never "none". Markers found before the failure are still listed. The report names a
    root that is a symbolic link on a line of its own and does not follow it. Printing "none"
    when `find` or `grep` fails had been a known limit of 0.5. The review of the commit that
    closes audit 0011 added it there, after the owner marked that step done. Two limits remain:
    - when `find` or `grep` fails, the report does not say which file or folder could not be
      read;
    - a symbolic link inside a searched root is not followed, and the report skips it without a
      line.

    One limit of its tests: on Windows, 8 checks of the marker search may be skipped. That
    happens when Git Bash's `ln -s` makes a copy instead of a link. They are the test of links
    into the corpus (2 checks) and the six linked-root tests (6 checks). Those rules are then
    tested on macOS and Linux only. `test-scripts.sh` prints "skipped on Windows" but does not
    count the skips, so they show only as a lower total (audit 0012, F1).
  - "Done when" for every step: a list of checks that prove the step is done. The PR
    description maps each item to its evidence: a test, a commit or a file. The reviewer and
    the auditor check that list. The open steps get theirs in this step.
  - `scripts/merge-ready.sh`, test first. It waits until the four CI jobs are green on the
    exact head of the PR, and stops if the head moves. It also checks that the last verdict
    comment is APPROVED and quotes the tree of that head. The merge goes ahead only after it.
    Known limits:
    - the tests' `gh` stand-in returns the output of the `--jq` projections, not GitHub's JSON.
      So the projections are not tested. They pick the last verdict, and the name, result and
      start time of each check. A wrong projection shows only on a real pull request;
    - the author of the verdict comment is not checked. Only collaborators may comment while
      the interaction limit lasts (`CLAUDE.md`);
    - checks are told apart by name only. A run started by hand on the same head
      (`workflow_dispatch`) replaces the pull request run of the job with the same name. A
      finished attempt with no start time counts as the oldest. So it is ignored when a timed
      attempt of the same name exists, even when it is red;
    - the local branch is not compared with the head of the pull request. A local branch that
      differs from it, ahead or behind, is not noticed. When it is ahead, the protection of
      `main` refuses the push;
    - when the head is an audit report pushed alone (`CLAUDE.md`, step 5), no verdict quotes its
      tree, so the script says "not ready". The owner decides what then (question below);
    - only the last verdict counts. A verdict of a commit not yet pushed makes an approved head
      "not ready" until that commit is pushed.
  - Model by risk. Sonnet writes routine code. Opus writes the code for cryptography and for
    R28–R34. The rule scripts and the hooks protect, so this step decides whether they count as
    routine code. Reviews and audits stay on Fable. A PR holds about 400 changed lines; a bigger
    step is split into slices, and the PR says what is left.
  - `docs/lessons.md`: lessons learnt on the way of working, each with its date, its source and
    what to do. Agents never watch CI themselves; only the main session does, so that GitHub's
    API limit is not used up. The first lessons come from audit 0011:
    - post each review verdict on the PR when its round ends, not together with the commit (F4);
    - give the owner's decisions in English in PR texts and comments (F5).
  - Two rules the owner added on 2026-11-26 (audit 0013), now in `CLAUDE.md`:
    - a session that must end commits only an APPROVED tree with no point that never moves;
      any other work stays uncommitted, with a state comment on the PR (F1);
    - owner's decisions on requirements taken while a step is open go into that step's branch
      (F3).
  - Questions for the owner, from audit 0012 and from one review; this step decides them:
    - F1: must the linked-root and corpus-link tests also run on Windows, for example with a
      `find` stand-in? Must `test-scripts.sh` count its skips, as `test-cleanup.sh` does?
    - F2: a missing test moved as a minor point from a0fba6d to the next commit, and two
      behaviour fixes counted as minor rounds. Must `CLAUDE.md` say what separates a missing
      test from "one more assertion"? Or must any behaviour fix get CHANGES NEEDED?
    - F3: on 2026-11-25 the owner delegated the choices that an audit leaves to the owner:
      "choose the solution that serves the goal and is coherent with earlier choices". Only the
      message of 72b89f3 and a PR #4 comment record it. Does it stand as a rule, with its limits
      written in `CLAUDE.md`? Or did it apply to audit 0011 only?
    - From the review of `scripts/merge-ready.sh`: an audit report pushed alone gets no review,
      so no verdict quotes its tree. May the merge then go ahead on the verdict of the commit
      before it, with CI green on the report? Or must the report always be pushed with a
      reviewed commit?
    - Note of audit 0012, not a finding. Four of the five commits in its range mainly close
      minor points moved from the commit before. The owner may weigh it when this step sets the
      size of a PR.

## Phase 1: how do we write files safely, before any cryptography?

With pure functions for names and confirmation, and a writer that never overwrites.

- [x] 1.0 Envelope names (`is_envelope`, R1a): delivered with the project setup (0.1).
- [ ] 1.1 Portable names (`names` module, R32):
  `portable_name(raw) -> PortableName { name, changed }`.
  - Tests, one per rule:
    - forbidden characters;
    - control characters;
    - trailing dot and space;
    - reserved Windows names (any case, with extension, superscript digits);
    - leading `-` and `.`;
    - `.` and `..`;
    - invalid UTF-8;
    - NFC;
    - the 255-byte/255-unit limit, without breaking a character or the extension;
    - an empty result, which gives the fallback name.
  - Property tests (`proptest`): the output is always valid on all three systems, and idempotent
    (`portable(portable(x)) == portable(x)`).
- [ ] 1.2 Collision key and free name (R17, R32): `collision_key` ignores case and
  normalization. `next_free_name("x.pdf", taken)` gives `x (1).pdf`, `x (2).pdf`..., still
  within the length limit.
- [ ] 1.3 Output name from the envelope name (R16; R18 without content sniffing for now):
  `Relazione.pdf.p7m` -> `Relazione.pdf`, nested `.pdf.p7m.tsd`, uppercase extensions.
- [ ] 1.4 i18n skeleton (R27): pick the mechanism (Fluent or `rust-i18n`, decided with the
  user), English and Italian, `--lang`, OS language detection. Needed before any message below.
  First decide the questions "Before 1.4" in `docs/design.md`.
- [ ] 1.5 Walk and count (R1b, R2, R19, R28). First decide the questions "Before 1.5" in
  `docs/design.md`.
  - One or more folders, a row per folder and the total.
  - Regular files only. Symbolic links met during the walk are not followed (a selected one is
    resolved), and hidden folders are skipped; both are listed in the report. Unreadable folders
    are listed.
  - Two counts (files to process, files of any kind), total size, subfolders.
  - Detection of sensitive folders: drive roots, home, Desktop, Documents, system folders,
    network share roots.
  - Detection of a risky run: a sensitive folder, or more than 10,000 files of any kind over all
    the folders, subfolders included.
- [ ] 1.6 Confirmation logic (R28–R30). First decide the questions "Before 1.6" in
  `docs/design.md`.
  - Pure functions turn the counts, the folder, the way the run started (terminal, dialog via
    `--interactive`, or script) and `--plan` into the question to ask. They also parse the
    answer.
  - The question is a typed count (R28 risky run, R29) or a yes/no question with default No
    (R30). Typestate `ConfirmedPlan`.
  - The dialogs themselves come with the menus (5.2).
- [ ] 1.7 Safe writer (R31). First decide the questions "Before 1.7" in `docs/design.md`.
  - `create_new`, the next free name on a race, removal of partial files.
  - The two-step replace of cache files and the manifest: a temporary file, then a rename.
  - Writing stays inside the folder (`..`, symbolic links); free-space check; re-check of
    originals.
  - The folder snapshot test helper (R34) is introduced here and used from now on.

## Phase 2: how do we open envelopes end to end?

With a BER reader, a CMS parser, one thin run of the whole flow, and a count of the signatures
inside a PDF.

- [ ] 2.1 `ber` reader: definite and indefinite lengths, limits on depth and size, checked
  arithmetic; fuzz target.
- [ ] 2.2 `cms` SignedData parsing: encapsulated content, certificates, signer infos (no
  verification yet); base64 envelopes; nested layers (R3, R4, R7).
- [ ] 2.3 End-to-end slice: `check` and `extract` on simple fixtures through the real flow.
  - Minimal console output with `--plain` and `--no-color` (R35); minimal JSON (R15).
  - Written documents recorded in the report with SHA-256, and `undo` (R33).
  - The first end-to-end tests in `tests/*.rs` use `assert_cmd` and `predicates`, declared in
    `Cargo.toml` since 0.1 (audit 0001, F12).
- [ ] 2.4 Signatures inside a signed PDF are found and counted (R50). Until 4.1 and 4.2 exist,
  the count and "not verified" go into the minimal output of 2.3. First decide the questions
  "Before 2.4" in `docs/design.md`. Negative tests: a malformed PDF, a PDF with no signature,
  and a document that only looks like a PDF.

## Phase 3: how do we verify signatures and time stamps?

One layer at a time: cryptography, certificates, trusted lists, chains, time stamps, revocation.

- [ ] 3.1 `crypto`: digests, RSA PKCS#1 v1.5, RSA-PSS, ECDSA P-256/P-384/P-521 (R8). First
  decide the question "Before 3.1" in `docs/design.md`.
- [ ] 3.2 `x509`: certificate fields, key usage, qualified/QSCD statements, validity (R9). First
  decide the question "Before 3.2" in `docs/design.md`.
- [ ] 3.3 `xmldsig`: exclusive C14N and XML signature verification (R44), test first, fuzzed
  like `ber`.
- [ ] 3.4 `tsl`: LOTL and national lists, signatures verified, embedded LOTL and Italian list,
  service history (R44, R48).
- [ ] 3.5 Choice of lists from the certifiers' countries, download, cache, `--trust-lists`,
  `--offline` (R45–R47). First decide the questions "Before 3.5" in `docs/design.md`.
- [ ] 3.6 Chain building against the TSL and the system store (R10). First decide the questions
  "Before 3.6" in `docs/design.md`.
- [ ] 3.7 Countersignatures (R11); `tsp`: RFC 3161, `.tsd`, `.m7m` (R5, R12); detached `.p7s`
  (R6). First decide the question "Before 3.7" in `docs/design.md`.
  - A time stamp is a proved time (R9) only if it verifies per R12, with a chain to a
    trusted-list TSA.
  - Negative test: a forged or untrusted time stamp changes no verdict.
- [ ] 3.8 Content sniffing for names without a usable extension (R18).
- [ ] 3.9 Revocation (R49). First decide the questions "Before 3.9" in `docs/design.md`.
  - Data embedded in the signature, a CRL per CA with cache, one check per certificate,
    "revocation not checked" offline.
  - Negative tests:
    - revoked before and after the time stamp;
    - revoked with no time stamp (cannot be determined, never invalid);
    - stale or forged embedded data;
    - a forged or oversized CRL;
    - a CRL older than the reference time;
    - an expired certificate no longer listed;
    - a distribution point outside `http`/`https`.
  - Also: an embedded CRL older than the reference time when the CA's CRL cannot be fetched
    ("revocation not checked").

## Phase 4: what does the user see?

A console summary, an accessible HTML report, JSON and a translated command line.

- [ ] 4.1 Console summary, colours with contrast, exit codes (R13, R35), with the line on PDF
  signatures not verified (R50).
- [ ] 4.2 Accessible HTML report, WCAG 2.2 AA (R14, R36), with the PDF signatures not verified
  (R50), checker in CI (R39). First decide the questions "Before 4.2" in `docs/design.md`.
- [ ] 4.3 Full `--json` (R15), with the PDF signatures not verified (R50); parallel processing
  with a stable output order (R23).
- [ ] 4.4 Command line and translated help, interactive end of run (R19, R20, R37). First decide
  `--open`, `--threads`, `extract --no-report` and double-click detection (questions "Before
  4.4" in `docs/design.md`).

## Phase 5: how does it fit into the system?

Through a context menu with native dialogs, recorded in a manifest so that `uninstall` can
remove it.

- [ ] 5.1 Install manifest (R41). First decide how `create_new` applies to registry keys and
  `.workflow` folders, and the other questions "Before 5.1" in `docs/design.md`.
- [ ] 5.2 Context menu per OS (R21, R38) with the confirmation dialogs (R30); Windows "Installed
  apps" entry (R42). First decide the questions "Before 5.2" in `docs/design.md`: Enter in a
  number field, what the shorter dialog summary must show, and the other questions.
- [ ] 5.3 `uninstall` (R40–R43). First decide what happens to a file in the cache folder that
  the tool did not write (questions "Before 5.3" in `docs/design.md`).

## Phase 6: how do we release it?

As one self-contained executable per platform, tested on the company PC before `1.0.0`.

- [ ] 6.1 Builds for all targets; `.deb`, `.rpm`, `.tar.gz` (R24, R25); one self-contained
  executable per platform, pure Rust (R22, enforced by `cargo deny`); version tag (R26).
- [ ] 6.2 Test on the company Windows PC (antivirus, SmartScreen, AppLocker) with the real
  corpus.
- [ ] 6.3 Manual accessibility checks, `docs/accessibility.md` (R39); user guide (R37).
- [ ] 6.4 `1.0.0` when ready to replace the old tool. Before it, every case of R34 has a test.

## Phase 7: what comes in version `2.0.0`?

Version `2.0.0` (R26) comes after `1.0.0`. It verifies the CMS signatures inside a PDF that R50
only reports, and evaluates the formats of "What do we evaluate for version 2?" in `docs/design.md`.

- [ ] 7.1 PAdES: the signatures inside a signed PDF are verified with the CMS verification of
  phase 3 (R8–R12, R49). First the owner decides the questions "Before 7.1" in
  `docs/design.md` and updates R50.
- [ ] 7.2 The other formats and cases of "What do we evaluate for version 2?". Each one the
  owner keeps gets a requirement first, then its own step.

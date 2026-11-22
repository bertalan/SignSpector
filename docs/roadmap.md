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
- [ ] 0.1 First commit and push to `main` (after review of the file list). From then on: one
  branch and one draft PR per step, coherence audit every 3 commits (`CLAUDE.md`).
- [ ] 0.2 GitHub Actions CI on Windows, macOS, Linux: fmt, clippy, nextest, doctests, cargo deny,
  `scripts/check-public.sh --tree HEAD`. Windows tests run here, no USB stick needed.
- [ ] 0.3 Fixture generator `scripts/make-fixtures.sh` (Homebrew `openssl@3`): test CA, signers,
  simple `.p7m`/`.p7s`, `.tsd`. Synthetic identities only, private keys never committed
  (generated at test time or kept in `target/`).

## Phase 1: safe writing core (no cryptography)
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
- [ ] 1.5 **Walk and count** (R1b, R2, R28): regular files only, symbolic links not followed,
  unreadable folders listed; count, total size, subfolders. Risky-folder detection (drive
  roots, home, Desktop, Documents, system folders, > 10,000 envelopes).
- [ ] 1.6 **Confirmation logic** (R28–R30): pure functions turning (counts, folder, terminal or
  not, flags) into the question to ask and parsing the answer; typed count; `--yes --expect`.
  Typestate `ConfirmedPlan`. Tests: Enter, `n`, wrong number, non-terminal without `--yes`.
- [ ] 1.7 **Safe writer** (R31): `create_new`, next free name on race, removal of partial files,
  stays inside the folder (`..`, symbolic links), free-space check, re-check of originals.
  Folder snapshot test helper (R34) introduced here and used from now on.

## Phase 2: opening envelopes (thin slice)
- [ ] 2.1 `ber` reader: definite and indefinite lengths, limits on depth and size, checked
  arithmetic; fuzz target.
- [ ] 2.2 `cms` SignedData parsing: encapsulated content, certificates, signer infos (no
  verification yet); base64 envelopes; nested layers (R3, R4, R7).
- [ ] 2.3 End-to-end slice: `check` and `extract` on simple fixtures through the real flow,
  minimal console output with `--plain`, `--no-color` (R35), minimal JSON (R15), write log
  with SHA-256 and `undo` (R33).

## Phase 3: verification
- [ ] 3.1 `crypto`: digests, RSA PKCS#1 v1.5, RSA-PSS, ECDSA P-256/P-384/P-521 (R8).
- [ ] 3.2 `x509`: certificate fields, key usage, qualified/QSCD statements, validity (R9).
- [ ] 3.3 `tsl`: embedded AgID list, parsing, online refresh, cache, offline (R10).
- [ ] 3.4 Chain building against the TSL and the system store (R10).
- [ ] 3.5 Countersignatures (R11); `tsp`: RFC 3161, `.tsd`, `.m7m` (R5, R12); detached `.p7s` (R6).
- [ ] 3.6 Content sniffing for names without a usable extension (R18).

## Phase 4: output
- [ ] 4.1 Console summary, colours with contrast, exit codes (R13, R35).
- [ ] 4.2 Accessible HTML report, WCAG 2.2 AA (R14, R36), checker in CI (R39).
- [ ] 4.3 Full `--json` (R15); parallel processing with stable output order (R23).
- [ ] 4.4 Command line and translated help, interactive end of run (R19, R20, R37).

## Phase 5: system integration
- [ ] 5.1 Install manifest (R41).
- [ ] 5.2 Context menu per OS (R21, R38); Windows "Installed apps" entry (R42).
- [ ] 5.3 `uninstall` (R40–R43).

## Phase 6: release
- [ ] 6.1 Builds for all targets; `.deb`, `.rpm`, `.tar.gz` (R24, R25); version tag (R26).
- [ ] 6.2 Test on the company Windows PC (antivirus, SmartScreen, AppLocker) with the real corpus.
- [ ] 6.3 Manual accessibility checks, `docs/accessibility.md` (R39); user guide (R37).
- [ ] 6.4 `1.0.0` when ready to replace the old tool.

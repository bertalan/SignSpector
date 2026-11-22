# SignSpector: requirements and design

Status: **draft**, to be completed with the author. Sections marked *To decide* are open.

## The idea

Offices receive and archive documents signed digitally (CAdES `.p7m`, detached `.p7s`) and
time-stamped (`.tsd`, `.m7m`), often nested (a `.p7m` inside a `.p7m`, a `.tsd` around a
`.p7m`). Opening them one by one is slow and tells little about the signatures. SignSpector
takes a folder, finds every such file, opens all the layers, checks signatures, certificates and
time stamps, and produces a report anyone can read. On request it saves the signed documents
beside the originals, ready to open.

## Requirements

### Finding files
- R1a. A name is an envelope when its extension is `.p7m`, `.p7s`, `.tsd` or `.m7m`, ignoring
  case; purely lexical, any bytes allowed in the rest of the name (non-UTF-8 names on Linux).
  *(done: `is_envelope`)*
- R1b. Walk a folder recursively; only regular files are checked with R1a (a folder named
  `archivio.p7m` is not an envelope).
- *To decide*: a file named exactly `.p7m` (no stem) is not an envelope today: list it in the
  report as skipped? Are stand-alone time-stamp responses `.tsr` an input format?
- R2. Unreadable folders are reported and skipped; the walk goes on. Symbolic links are not
  followed and hidden folders (name starting with `.`) are skipped; both are listed in the
  report, so nothing is left out silently.

### Opening envelopes
- R3. Read CMS SignedData in BER, including indefinite lengths (common in real files), and in
  base64 form.
- R4. Unwrap nested layers until the signed document is reached; report each layer.
- R5. RFC 5544 TimeStampedData (`.tsd`) and `.m7m` (MIME with signature and time stamp).
- R6. Detached `.p7s`: look for the signed file beside it.
- R7. A malformed file never stops the run: it becomes a "problem" line for that file (source wording in English, translated per R27).

### Verifying
- R8. Each signature: digest of the content, signed attributes, signature (RSA PKCS#1 v1.5,
  RSA-PSS, ECDSA P-256/P-384/P-521; SHA-1/256/384/512).
- R9. Signer certificate: validity at the reference time (time stamp if present, otherwise
  signing time, otherwise now), key usage (non-repudiation), qualified / QSCD flags.
- R10. Chain to a CA of a **European trusted list** (R44–R48): the national list of the
  certifier's country, reached through the EU List of Trusted Lists; optionally to the system
  trust store, labelled "recognised by the system" (translated per R27).
- R11. Countersignatures.
- R12. Time stamps (RFC 3161): imprint matches, TSA signature and chain valid.
- *To decide*: revocation (CRL/OCSP)? Brainpool curves? Download of missing intermediates (AIA)?

### Output
- R13. Console summary per file, in the user's language (R27), with colours; exit codes 0 all fine / 1 problems /
  2 cannot run.
- R14. HTML report (one self-contained file) in the analysed folder or at `--report <file>`.
- R15. `--json <file>` with the same information, for scripts.
- *To decide*: layout and content of the report (start from the old tool's report as a sketch?).

### Extracting
- R16. `check` (the default) writes nothing but the report. `extract` writes the signed
  documents beside the originals (`Relazione.pdf.p7m` -> `Relazione.pdf`) after the two
  confirmations of R28 and R29: the typed confirmation is the safeguard.
- R17. Never overwrite: same content already there -> nothing to do; different content ->
  `Relazione (1).pdf`. Originals are never modified, moved or renamed.
- R18. Name without a usable extension: guess it from the content (PDF, ZIP-based office
  formats, XML, images).

### Using it
- R19. Command line. Commands: `check <dir>` (default), `extract <dir>`, `undo <report>`,
  `install-menu`, `uninstall-menu`, `uninstall`. **There is no `--apply`.** Every command that
  changes files or the system (`extract`, `undo`, `install-menu`, `uninstall-menu`,
  `uninstall`) works the same way: it shows the exact plan and acts only after the number of
  items is typed (R29); without a terminal it needs `--yes --expect <n>` (R30); `--plan` prints
  the plan and exits without asking. `check` changes nothing. Options: `--open`, `--report`,
  `--no-report`, `--report-lang <code>`, `--json <file>`, `--threads`, `--offline`,
  `--trust-lists <auto|all|codes>`, `--trust-list <file>`, `--lang <code>`, `--interactive`,
  `--plain`, `--no-color`, `--plan`, `--yes`, `--expect <n>`. Help translated (R27).
- R20. Interactive end of run (double-click on Windows, context menu, `--interactive`): after
  the analysis, offer to view the report or to extract; extraction goes through the write
  plan and its confirmation (R29) and reuses the analysis already done.
- R21. `install-menu` / `uninstall-menu` (plan and typed confirmation, R19) for the file manager's
  context menu: Windows per-user registry keys (no admin, no PowerShell); macOS Quick Actions;
  Linux Nautilus script and Dolphin service menu. Full removal: `uninstall` (R40–R43).

### Non-functional
- R22. One self-contained executable per platform, pure Rust dependencies.
- R23. Files processed in parallel, output printed in a stable order.
- R24. Targets: Windows x86_64, macOS arm64 + universal, Linux x86_64 static (musl).
- R25. Linux packages: `.deb`, `.rpm` and a generic `.tar.gz` (static musl binary, works on
  any distribution). Built on the Mac from the musl binary with `cargo-deb` and
  `cargo-generate-rpm` (pure Rust, no dpkg/rpmbuild needed).
- R26. Versioning: SemVer starting from `0.1.0`; `0.x` while behaviour and options may still
  change, `1.0.0` when the tool is ready to replace the old one in production. The old tool's
  numbering is not continued. Every release is a git tag `vX.Y.Z`.

### Languages
- R27. The interface (console messages, `--help`, HTML report, JSON field values meant for
  people, user guide) is translated. Language = the one chosen by the user (`--lang it`,
  or a saved preference), otherwise the operating system's language, otherwise English.
  Source language English; first translation Italian; more can be added without code changes.
- *To decide*: translation mechanism (e.g. Fluent `.ftl` files embedded in the executable, or
  `rust-i18n`), OS language detection (`sys-locale`), where the preference is saved, how
  dates and numbers are formatted per language.
- The report is written in the interface language by default; `--report-lang <code>` writes it
  in another one (for example to send it to an office abroad).

### Confirmation and write safety
Nothing is ever processed right after a folder is chosen, and nothing is written without a
second, separate confirmation. Writing never replaces an existing file.

- R28. **Confirm before analysing.** After the folder is chosen the tool only counts (no
  envelope is opened) and asks, default No (Enter alone cancels):
  folder, number of envelopes, total size, number of subfolders, unreadable folders that will
  be skipped. Zero envelopes: say so and stop. **Risky folder**: root of a drive or volume,
  the user's home, Desktop, Documents, system folders (`C:\Windows`, `Program Files`,
  `/System`, `/usr`, `/etc`...), network share roots, or **more than 10,000 envelopes**: a
  stronger warning and the user must type the number of envelopes.
- R29. **Confirm before writing.** Extraction first builds the complete write plan and shows
  it: new documents, documents already present with identical content (not rewritten),
  documents saved under an alternative name `x (1).pdf`, and "existing files modified: 0"
  (always zero, shown as a guarantee). The full list can be viewed. To proceed the user types
  the number of documents to write (language-neutral, cannot be confirmed by a stray key).
- R30. **Non-interactive use.** Without a terminal (`std::io::IsTerminal`: scripts, redirected
  input) there is no prompt and no implicit yes: the run needs `--yes --expect <n>` and stops
  with exit code 2 if the count found differs from `<n>`. A `y` arriving on a pipe is not a
  confirmation. The same applies to `undo` (R33).
- R31. **Never overwrite, never write outside.**
  - In code, writing requires a `ConfirmedPlan` that only the confirmation step can build
    (typestate): a path that writes without confirmation does not compile. Originals are held
    in a read-only `Original` type that write functions do not accept.
  - Every file is created with `OpenOptions::create_new(true)`: the OS refuses if the name
    exists, even if the file appeared after the plan; then the next free name `(2)`, `(3)`...
    is used. A partly written file (error, disk full) is removed, only if we created it.
  - Before writing, each original is re-checked against the analysis (size, mtime, SHA-256);
    if the folder changed, the plan is rebuilt and confirmed again.
  - Every target must stay inside the chosen folder after resolving `..` and symbolic links.
  - Free disk space is checked before starting. Ctrl+C finishes the current file, stops, and
    the report records what was done.
- R32. **Portable file names.** Names taken from envelopes (and the `(n)` variants) must be
  valid on **Windows, macOS and Linux at the same time**, and on FAT32/exFAT file systems,
  whatever system the tool runs on (archives move between systems):
  - removed or replaced: `/` `\` `:` `*` `?` `"` `<` `>` `|`, NUL and control characters
    U+0000–U+001F and U+007F; trailing dots and spaces; leading spaces;
  - reserved Windows names, with or without extension and in any case: `CON`, `PRN`, `AUX`,
    `NUL`, `COM0`–`COM9`, `LPT0`–`LPT9` (also with superscript digits `¹²³`);
  - leading `-` (taken as an option by shell commands) and leading `.` (hidden on macOS and
    Linux) are neutralised; `.` and `..` are never names;
  - invalid UTF-8 or unpaired surrogates are replaced; names are stored in Unicode NFC;
  - length: at most 255 UTF-8 bytes and 255 UTF-16 units per component, cut without breaking
    a character or the extension;
  - collisions are checked **case-insensitively and normalization-insensitively** (NTFS and
    APFS default are case-insensitive; APFS treats NFC/NFD as the same name), so two
    documents never compete for "names" that the file system sees as equal;
  - the original name, when changed, is shown in the report.
- R33. **Undo.** The report records every file written with its SHA-256.
  `signspector undo <report>` removes only files written by SignSpector whose content still
  matches that hash; changed or missing files are listed and left alone; originals are never
  touched. Like `extract`: it shows what it would remove and removes only after the typed
  count (R29); `--yes --expect <n>` without a terminal (R30).
- R34. **Proof by tests.** A shared test helper snapshots the whole folder (paths + SHA-256)
  before and after every end-to-end test: originals identical, nothing changed but the
  confirmed plan. Dedicated tests: empty answer, `n`, wrong number; file appearing between
  plan and write; names with `..`, reserved names, forbidden characters, NFC/NFD and case
  collisions, over-long names; symbolic link pointing outside; disk full (simulated);
  no terminal without `--yes`; `undo` with a modified file.

### European trusted lists
Signatures may come from any EU/EEA country (Italy, Romania, France...). Trust is anchored in
the EU **List of Trusted Lists** (LOTL, `https://ec.europa.eu/tools/lotl/eu-lotl.xml`,
signed by the European Commission). It points to each national trusted list and names the
certificates that sign it (checked 2026-11-22: LOTL no. 398, 43 pointers: EU-27, Iceland,
Liechtenstein, Norway, United Kingdom).

- R44. **Chain of trust.** The executable embeds the LOTL and the Commission's LOTL signing
  certificates (published in the Official Journal of the EU). A national list is used only if
  its XAdES signature verifies against the certificates the LOTL names for that country; the
  LOTL only if it verifies against the embedded Commission certificates. Italy is one country
  among the others. The repository stores no trusted list: the release build downloads the
  current LOTL and the Italian list and embeds them, so the tool works offline out of the box;
  at the first run with network the tool refreshes them into its cache, which then takes
  precedence (R47).
- R45. **Automatic choice.** The analysis collects the country of every certifier found in the
  files (`C=` of the issuing CA) and loads only those lists: from the cache if still valid,
  otherwise downloaded. The summary before confirmation names them, for example "signatures
  from 3 countries: Italy, Romania, France; lists: Italy and France up to date, Romania
  downloaded now".
- R46. **Settable.** `--trust-lists auto` (default) / `all` / `it,ro,fr`; `--trust-list <file>`
  loads a list by hand; `--offline` uses only the embedded copies and the cache. A missing list
  is reported as such ("list of Romania not available offline"), never as an invalid signature.
- R47. **Cache.** Lists are cached in the SignSpector cache folder and refreshed when their own
  `NextUpdate` date passes; `uninstall` removes the cache (R40).
- R48. **Verdicts.** Qualified status is checked at signing time using the service history in
  the list (a service withdrawn later still validates an earlier signature). A certifier on no
  list is reported as "not on a European trusted list", distinct from "invalid signature". Any
  country listed in the official LOTL is accepted, the United Kingdom included. The report
  names every list used (country, sequence number, issue date).
- Cost: verifying XAdES needs XML canonicalisation (exclusive C14N) and XML signature
  verification; no mature pure-Rust library exists, so it is written here, test first, as
  carefully as the BER reader.

### Accessibility
Legal frame (Italy/EU): Legge 4/2004 ("Legge Stanca", as amended by D.Lgs. 106/2018) and the
AgID guidelines on the accessibility of IT tools, which refer to the harmonised standard
**EN 301 549** (ch. 11 software, ch. 12 documentation and support, ch. 9 web content = WCAG).
The European Accessibility Act (Directive 2019/882, D.Lgs. 82/2022) probably does not cover
this tool, but meeting EN 301 549 covers it too. Targets: **EN 301 549** for the program and
**WCAG 2.2 level AA** for the HTML report and the user guide. Whoever deploys the tool in a
public administration checks the applicable obligations (e.g. accessibility statement).

- R35. **Console.**
  - Information is never conveyed by colour or symbols alone: every status is a word
    ("OK", "Warning", "Error" in the user's language); colours only reinforce it, with
    sufficient contrast on both light and dark terminals, never red/green as the only
    difference. Colours off with `NO_COLOR`, `--no-color`, or when output is not a terminal.
  - No box drawing, ASCII art or tables made of spaces for essential information: linear
    text, one fact per line, read well by NVDA, JAWS, Narrator, VoiceOver and Orca.
  - Progress does not flood screen readers: no spinners, no rewriting the same line many
    times a second. `--plain` (also `SIGNSPECTOR_PLAIN=1`) gives line-by-line output with a
    progress line at most every few seconds and a final summary.
  - Prompts: the full question on one line, with the possible answers and the default
    spelled out in words; keyboard only; **no time limits** on any prompt.
  - Messages in plain language; every error says what happened, which file, and what the
    user can do.
- R36. **HTML report (WCAG 2.2 AA).**
  - `lang` set to the report language; meaningful `<title>`; landmarks (`header`, `main`,
    `nav`) and a "skip to content" link; headings in order, no level skipped.
  - Real tables with `<caption>` and `<th scope>`; status shown as text (with optional icon
    that has a text alternative), never by colour alone.
  - Contrast at least 4.5:1 for text and 3:1 for UI parts and icons, in light and dark mode
    (`prefers-color-scheme`); respects `prefers-reduced-motion`.
  - Works at 200% zoom and reflows at 320 CSS px width without horizontal scrolling
    (except data tables, which scroll on their own).
  - Fully keyboard operable (`<details>`/`<summary>` for expandable parts), visible focus,
    no keyboard traps; works without JavaScript; descriptive link texts; prints readably.
- R37. **Documentation and help** (EN 301 549 ch. 12): `--help` and the user guide are plain
  text / HTML (no scanned or untagged PDF), translated, and include a section describing the
  accessibility features (`--plain`, `--no-color`, keyboard use, screen readers).
- R38. **Context menu and dialogs**: only native OS menus and, if ever added, native dialogs
  (e.g. `rfd`), which inherit the OS accessibility; clear entry labels in the user's language.
  No custom-drawn GUI.
- R39. **Verification.** Automated: unit tests on the HTML structure (lang, headings, table
  headers, no colour-only status) and an accessibility checker on sample reports in CI (e.g.
  `axe-core` or `pa11y`); console tests with `NO_COLOR` and `--plain`. Manual before each
  release: NVDA on Windows, VoiceOver on macOS, Orca on Linux, keyboard only, 200% zoom,
  Windows high contrast. Results recorded in `docs/accessibility.md`.

### Uninstalling
- R40. **`signspector uninstall`** removes everything SignSpector added to the system, and
  only that: context menu entries, the Windows "Installed apps" entry (R42), trust-list cache,
  saved preferences, logs. Same rule as every command that changes something (R19): it shows
  the exact list of what it would remove and removes only after the typed count (R29);
  `--yes --expect <n>` without a terminal (R30); accessible like the rest (R35).
- R41. **Only what we installed.** `install-menu` records every item it creates (path or
  registry key, plus a hash of the content) in a manifest in the SignSpector config folder;
  `uninstall` removes only manifest items that still match, reports changed or foreign items
  and leaves them. If the manifest is lost, entries are recognised by an explicit SignSpector
  marker, never by guessing. Running it twice is harmless.
- R42. **Per platform.**
  - Windows: per-user, no admin: registry keys under `HKCU`, plus an uninstall entry in
    `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\SignSpector` so the user finds it
    in Settings → Apps; its `UninstallString` runs `signspector.exe uninstall --interactive`,
    which shows the list and asks for the typed count in a console window.
    A running `.exe` cannot delete itself: the tool says where it is so the user can delete it
    (no PowerShell, no scheduled tricks).
  - macOS: Quick Actions in `~/Library/Services`, caches in `~/Library/Caches/SignSpector`,
    preferences in `~/Library/Application Support/SignSpector`.
  - Linux: Nautilus script, Dolphin service menu, `~/.cache/signspector`,
    `~/.config/signspector`. `.deb`/`.rpm` remove only system files they installed; the
    per-user items are removed by `signspector uninstall` (the package's removal message
    says so).
- R43. **User data is never removed**: originals, extracted documents and reports stay; at
  the end the tool lists what it left in place on purpose and where the executable is.

## Architecture (proposal)

Library crate with one module per concern, the executable only parses arguments and prints:

| Module | Role | Candidate crates |
|---|---|---|
| `names` | portable file names, collision keys, free names (R32, R17) | `unicode-normalization` |
| `i18n` | translation layer, language choice (R27) | to decide (1.4) |
| `confirm` | counts, questions, typed answers, `ConfirmedPlan` (R28–R30) | `std::io::IsTerminal` |
| `ber` | BER/DER reader, indefinite lengths, own code (RustCrypto `der` is DER-only) | none |
| `cms` | SignedData, signer infos, attributes, countersignatures | `ber` |
| `tsp` | RFC 3161 tokens, RFC 5544 `.tsd`, `.m7m` | `cms` |
| `crypto` | digests and signature checks | `sha1`, `sha2`, `rsa`, `p256`, `p384`, `p521`, `ecdsa` |
| `x509` | certificates, names, extensions, chain building | `x509-parser` |
| `xmldsig` | exclusive C14N, XML signature verification (R44) | `roxmltree`, own code |
| `tsl` | LOTL and national lists: embedded copies, choice by country, refresh, cache (R44–R48) | `roxmltree`, `flate2`, `ureq` + rustls, `directories` |
| `scan` | folder walk, per-file pipeline, parallelism | `std::thread::scope` |
| `extract` | safe writer, write log, `undo` (R31, R33), content type (R18) | `zip` |
| `report` | console, HTML, JSON | `serde_json`, `anstream` |
| `menu` | context-menu install, manifest, `uninstall` (R21, R40–R43) | `winreg` (Windows) |
| `main.rs` | arguments, help | `clap` |

The order of work is in `roadmap.md` (safety-critical, pure parts first).

## Test data

- Synthetic fixtures in `tests/fixtures/`, generated by a script (Homebrew `openssl@3`:
  `openssl cms -sign`, `openssl ts`) and by Rust test helpers for what OpenSSL cannot produce:
  BER indefinite lengths, nested envelopes, `.tsd`, base64, RSA-PSS, ECDSA, countersignatures,
  tampered content, expired and untrusted certificates, a fake TSL listing the test CA.
- Fuzzing of the `ber` and `cms` readers (`cargo fuzz`, needs nightly) once they exist: no input
  may panic or hang.
- Real documents stay on the Windows PC (`tests/corpus/`, git-ignored, personal data): used to
  check results by hand and, if useful, against the old tool's output.

## Building on the Mac

```sh
cargo build --release                                       # macOS, this machine
cargo build --release --target x86_64-apple-darwin          # macOS Intel
lipo -create -output dist/macos/signspector \
  target/aarch64-apple-darwin/release/signspector target/x86_64-apple-darwin/release/signspector
cargo build --release --target x86_64-pc-windows-gnu       # Windows (mingw-w64)
cargo zigbuild --release --target x86_64-unknown-linux-musl # Linux, static
x86_64-w64-mingw32-objdump -p target/x86_64-pc-windows-gnu/release/signspector.exe | grep 'DLL Name'
```

The Windows executable must import only system DLLs (checked: `KERNEL32`, `ntdll`,
`api-ms-win-*`). First milestone on the company PC: run the placeholder `.exe` from `cmd` to
confirm antivirus, SmartScreen and AppLocker accept a mingw-built executable.

## Recorded exceptions

- Until the translation layer exists (roadmap 1.4), the placeholder message in `src/main.rs` is
  the only hard-coded user-facing text; it goes away with 1.4.

## Open questions

- `ring` as the crypto provider of rustls (for the TSL refresh over HTTPS): it contains C and
  assembly, cross-compiles fine, and is the only provider not banned in `deny.toml`
  (`aws-lc-rs` is). Accept it as an exception to "pure Rust", or look for a pure-Rust provider
  (e.g. `rustls-rustcrypto`)? To decide before roadmap 3.5 (download of the lists).
- Does the company proxy require integrated authentication (NTLM/Kerberos) to reach the
  trusted lists (`ec.europa.eu` for the LOTL, `eidas.agid.gov.it` and the other national
  addresses)? If yes, Windows needs WinHTTP for the refresh.
- Revocation checks: wanted? (The old tool did not do them.)
- Brainpool curves, AIA download of missing intermediates: needed by the real files?

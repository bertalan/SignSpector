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
- R2. Unreadable folders are reported and skipped; the walk goes on. Symbolic links met during
  the walk (not a selected folder, R19, R28) are not
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
- R9. Signer certificate: validity at the reference time, key usage (non-repudiation),
  qualified / QSCD flags. The **reference time** is a proved time only: the signature's time
  stamp, or the time stamp of a `.tsd`/`.m7m` that contains the file (R5, R12). The
  signing-time attribute is written by the signer and proves nothing: without a time stamp
  the reference time is the time of the check, and the report shows the claimed time marked
  "claimed, not proved". The same reference time is used by R48 and R49.
- R10. Chain to a CA of a **European trusted list** (R44–R48): the national list of the
  certifier's country, reached through the EU List of Trusted Lists; optionally to the system
  trust store, labelled "recognised by the system" (translated per R27).
- R11. Countersignatures.
- R12. Time stamps (RFC 3161): imprint matches, TSA signature and chain valid.
- Revocation: R49. *To decide*: Brainpool curves? Download of missing intermediates (AIA)?

### Output
- R13. Console summary per file, in the user's language (R27), with colours; exit codes 0 all fine / 1 problems /
  2 cannot run.
- R14. HTML report (one self-contained file) in each analysed folder, covering that folder
  only, or at `--report <file>` (one file for the whole run).
- R15. `--json <file>` with the same information, for scripts.
- *To decide*: layout and content of the report (start from the old tool's report as a sketch?).

### Extracting
- R16. `check` (the default) writes no document. It writes only:
  - the HTML report, in each folder or at `--report <file>` (none with `--no-report`, R19);
  - the JSON file of `--json <file>` (R15);
  - the tool's own cache of trusted lists and CRLs (R44, R47, R49).

  The report and the JSON file never replace an existing file: they are created with
  `create_new`, and a name already taken gets the next free name (`(1)`, `(2)`...), as in R17.
  `check` and `extract` replace no file outside the tool's cache folder (R31). One exception
  writes documents in a `check` run: extraction chosen at the interactive end of run (R20),
  through R29. `extract` writes the signed documents beside the originals (`Relazione.pdf.p7m` ->
  `Relazione.pdf`) after the two confirmations of R28 and R29: typing the number of documents is
  the safeguard.
- R17. Never overwrite: same content already there -> nothing to do; different content ->
  `Relazione (1).pdf`. Originals are never modified, moved or renamed.
- R18. Name without a usable extension: guess it from the content (PDF, ZIP-based office
  formats, XML, images).

### Using it
- R19. Command line. Commands: `check <dir>...` (default), `extract <dir>...`, `undo <report>`,
  `install-menu`, `uninstall-menu`, `uninstall`. **There is no `--apply`, `--yes` or `--expect`.**
  Every command that changes files or the system shows the exact plan first and acts only after a
  person confirms. The one exception is what `check` writes on an ordinary folder from a script:
  the report (HTML and JSON) and the cache, with no question (R16, R30). Where the person is
  decides how (R30):
  - **at a terminal**: before analysing, a yes/no question (R28); for files found in a folder
    the user types the number (risky folder, R28; documents to write, R29); `undo`,
    `install-menu`, `uninstall-menu`, `uninstall` change only what the tool itself made and
    ask a yes/no question. Yes/no questions default to No, Enter alone cancels, and the
    answers and the default are written out in words in the user's language (R35, R27);
  - **from the context menu** (`--interactive`): the same confirmations (same number to type,
    same default) in a native dialog (R38), with the summary of R30, focus on Cancel;
  - **from a script** (no terminal, no `--interactive`): nobody can answer, so they refuse.

  `check` and `extract` take one or more folders (several can be selected in the file manager).
  They are counted and confirmed together: one summary with a row per folder (path, number of files
  to process, number of files of any kind) and the totals, one question for all. When the run is
  risky, the summary says why (the kind of folder, or the 10,000-file limit). The number typed is
  the total. A single risky folder makes the whole run risky, and the 10,000-file limit applies to
  the total (R28). A folder with no envelopes is shown with 0; if all are empty the run stops. The
  same folder given twice (also spelt differently: letter case, a symbolic link, a trailing slash),
  or a folder inside another selected one, is counted once, under the outer folder; the summary
  says so, and its envelopes go in the outer folder's report.

  `--interactive` says that a person is there even without a terminal: questions come in
  native dialogs (R30) and the run ends with the interactive end of run (R20). The
  context-menu entries and the Windows uninstall entry (R42) pass it. With a terminal the
  questions stay in the terminal and R20 still applies. If no dialog can be shown (no
  desktop session), `--interactive` refuses with exit code 2, like a script.

  `--plan` shows what the command would do and stops before doing it. It never writes
  anything, not even the report or the cache, and downloads nothing: it uses the embedded
  lists and those already in the cache.
  - `check --plan` only counts (R28; no envelope is opened) and prints the summary: no
    question, allowed everywhere, also from a script on a risky folder.
  - `extract --plan` builds the write plan of R29, which opens every envelope, so it asks the
    R28 question first (console or dialog), and from a script runs on an ordinary folder and
    refuses a risky one, like `check`. It also says which trusted lists a real run would
    download (R45).
  - For the other commands it lists the items, with no question, also from a script.

  Options: `--open`, `--report`, `--no-report`, `--report-lang <code>`, `--json <file>`,
  `--threads`, `--offline`, `--trust-lists <auto|all|codes>`, `--trust-list <file>`,
  `--lang <code>`, `--interactive`, `--plain`, `--no-color`, `--plan`. Help translated (R27).
  `--no-report` skips the report of an analysis. An extraction always writes its report, and
  its JSON file when `--json` is given, so that `undo` has the list of documents (R33; owner's
  decision, 2026-11-23).
- *To decide* (before roadmap 4.4): what `--open` and `--threads` do (R23 asks for parallel
  work, not an option); whether `extract --no-report` is refused as a usage error or accepted
  with a message saying the extraction report is written anyway.
- R20. Interactive end of run (double-click on Windows, context menu, `--interactive`): after
  the analysis, offer to view the report or to extract; extraction goes through the write
  plan and its confirmation (R29) and reuses the analysis already done. The first report is
  never rewritten: the extraction writes a second report beside it (next free name, R16) with
  the analysis and the documents written, and `undo` uses that one (R33). With `--json` it
  also writes a second JSON file beside the first. After `check --no-report` there is no first
  report: the extraction report is the only one.
- R21. `install-menu` / `uninstall-menu` (plan and yes/no question, R19) for the file manager's
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
  people, user guide) is translated. Language = the one chosen with `--lang it`, otherwise the
  operating system's language, otherwise English. No preference is saved; a command to save
  one can be added later, with its plan and question (R19).
  Source language English; first translation Italian; more can be added without code changes.
- *To decide*: translation mechanism (e.g. Fluent `.ftl` files embedded in the executable, or
  `rust-i18n`), OS language detection (`sys-locale`), how dates and numbers are formatted per
  language.
- The report is written in the interface language by default; `--report-lang <code>` writes it
  in another one (for example to send it to an office abroad).

### Confirmation and write safety
Nothing is ever processed right after a person chooses a folder, and no document is written
without a second, separate confirmation. `check` and `extract` never replace an existing file;
only the tool's own cache is refreshed in place (R16; the general rule is R31). A folder named in
a script has no person to ask: an ordinary folder is analysed (`check` writes only the report,
HTML and JSON, and the tool's cache, R16); a risky one is refused, only counted by `check
--plan`, and nothing is written (R30).

- R28. **Confirm before analysing.** After the folders are chosen the tool only counts (no
  envelope is opened) and asks, default No (Enter alone cancels):
  folder, number of files to process (the envelopes, R1a), number of files of any kind, total
  size, number of subfolders, unreadable folders that will be skipped. Zero envelopes: say so
  and stop. The interface calls the envelopes "files to process". **Risky folder**: root of a
  drive or volume, the user's home, Desktop, Documents, system folders (`C:\Windows`,
  `Program Files`, `/System`, `/usr`, `/etc`...), network share roots, or a folder that holds
  **more than 10,000 files of any kind**, subfolders included: a stronger warning and the user
  must type the number of files to process (envelopes). The 10,000 count covers the regular
  files of the folders the walk visits (R2). Files in hidden folders, behind symbolic links met
  during the walk or in unreadable folders are not counted. A file in overlapping folders
  counts once. A selected folder that is itself a symbolic link is resolved and counted (R19).
  Every path-based kind of risky folder is judged on the path after resolving symbolic links.
- R29. **Confirm before writing.** Extraction first builds the complete write plan and shows
  it: new documents, documents already present with identical content (not rewritten),
  documents saved under an alternative name `x (1).pdf`, and "existing files modified: 0"
  (always zero, shown as a guarantee). The full list can be viewed. To proceed the user types
  the number of documents to write (language-neutral, cannot be confirmed by a stray key).
- R30. **Three ways to confirm, never an implicit yes.**
  - Terminal (`std::io::IsTerminal` on input and output): questions in the console (R28, R29,
    R19).
  - Context menu: no terminal, started with `--interactive`: the same confirmations in a native
    dialog (R38), with a shorter summary than the console. The dialog lists every selected folder
    with its number of files to process (envelopes to analyse, R28; documents to write, R29), the
    total, the reason when the run is risky (R19) and the operation proposed, then asks the
    question. When a number is required (R28 risky folder, R29) it is typed in a text field and
    Confirm accepts only the right number; otherwise the dialog is a yes/no question. In every
    dialog the focus starts on Cancel; Enter alone and closing the window cancel; no time limit.
    *To decide* (before roadmap 5.2): whether the dialog also shows the count of files of any
    kind, as the console summary does (R19).
  - Script (no terminal, no `--interactive`): `extract`, `undo`, `install-menu`,
    `uninstall-menu`, `uninstall` and `check` on a risky folder (R28) stop with exit code 2
    and say that a person must confirm. A `y` or a number arriving on a pipe is not a
    confirmation. Only `check` on an ordinary folder, `check --plan`, `extract --plan` on an
    ordinary folder and `--plan` of `undo`, the menus and `uninstall` (a list) run.
    "Terminal" means both input and output are a terminal: with output redirected
    (`| tee log`, `> file`) the run counts as a script.
- R31. **Never overwrite, never write outside.**
  - In code, writing a document requires a `ConfirmedPlan` that only the confirmation step can
    build (typestate): a path that writes without confirmation does not compile. Originals are
    held in a read-only `Original` type that write functions do not accept.
  - Every file the tool writes is created with `OpenOptions::create_new(true)`, except two kinds
    of its own files: the files of its cache, under the names it derives itself (R47), and its
    install manifest (R41). These are refreshed safely: a new file is written with `create_new`
    under a temporary name in the same folder, then renamed over the old one; the tool never
    follows a symbolic link there and refuses a name that is not a regular file. Documents,
    reports, JSON files and menu items are all created this way: the OS refuses if the name
    exists, even if the file appeared after the plan. A document, report or JSON file then takes
    the next free name (`(1)`, `(2)`...); a menu item is reported and left (R41). A partly
    written file (error, disk full) is removed, only if we created it.
  - Before writing, each original is re-checked against the analysis (size, mtime, SHA-256);
    if the folder changed, the plan is rebuilt and confirmed again.
  - Every target must stay inside the selected folder its envelope was found in, after
    resolving `..` and symbolic links.
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
- R33. **Undo.** The report written by an extraction records every document written with its
  SHA-256 (an extraction at the interactive end of run writes its own report, R20).
  `signspector undo <report>` removes only files written by SignSpector whose content still
  matches that hash; changed or missing files are listed and left alone; originals are never
  touched. It shows what it would remove and removes it after a yes/no question (R19); never
  from a script (R30).
- R34. **Proof by tests.** A shared test helper snapshots the whole folder (paths + SHA-256)
  before and after every end-to-end test: originals identical, nothing changed but the
  confirmed plan. Dedicated tests: empty answer, `n`, wrong number; file appearing between
  plan and write; names with `..`, reserved names, forbidden characters, NFC/NFD and case
  collisions, over-long names; symbolic link pointing outside; disk full (simulated);
  `undo` with a modified file. Confirmation (R19, R28–R30):
  - from a script: every changing command, `check` and `extract --plan` on a risky folder,
    and `--interactive` without a desktop refused with exit 2; `check` on an ordinary folder,
    `check --plan` anywhere, `extract --plan` on an ordinary folder and `--plan` of `undo`,
    the menus and `uninstall` run without a question; output redirected counts as a script;
  - `--interactive` with a terminal keeps the questions in the terminal;
  - `--plan` writes nothing, not even the report or the cache, and downloads nothing;
  - `check` adds only its report to the folder (snapshot), and nothing with `--no-report`; an
    existing report or JSON file, also one named with `--report` or `--json`, is not replaced:
    the new one gets the next free name; `extract --plan` names the lists a real run would
    download; end-to-end tests point the cache to a temporary folder through the system's own
    variables (R47; Windows to decide), never the user's real one; a file in the cache folder
    under a name the tool does not derive is never replaced; a symbolic link or a folder at
    one of the tool's own names (cache or manifest) is refused, never followed; a CA whose name
    holds `../` or a separator gives a cache file named only by the hash, inside the folder;
  - only the manifest and the cache files are replaced: snapshots of the config and cache
    folders around `install-menu`, `uninstall-menu` and a list refresh;
  - `install-menu` run twice changes nothing; after a lost manifest, our marked items are
    recognised and a foreign item never enters the manifest;
  - with `--json`, an extraction at the interactive end of run writes a second JSON file and
    leaves the first; `extract --no-report --json f` still writes `f`;
  - interactive end of run (R20): documents are written only through R29, declining writes
    none, and an extraction writes a second report without touching the first; `undo` on the
    second report removes the documents, on the first it removes nothing and says so;
  - `extract --no-report` still writes the extraction report;
  - `install-menu` meeting a foreign item with the same name reports it, leaves it, and
    `uninstall` does not remove it;
  - the console summary shows both counts in each row and in the totals, and the reason for a
    risky run; the dialog shows the reason;
  - risky folder: more than 10,000 files of any kind (subfolders included) is risky even with
    few envelopes, and the number typed is the files to process; exactly 10,000 is not risky,
    10,001 is, also as a total over several folders; files in hidden folders, behind symbolic
    links met during the walk or in unreadable folders are not counted, a selected folder that
    is a symbolic link is resolved and counted, and overlaps are counted once;
  - time: a back-dated signing-time attribute changes no verdict; without a time stamp the
    report says "claimed, not proved" (R9);
  - yes/no question: Enter alone cancels, `y` on a pipe is refused, a number is not a yes;
  - several folders: the total is typed, one risky folder makes the run risky, the 10,000
    limit applies to the total, all folders empty stop the run, overlaps (also by letter
    case, symbolic link, trailing slash) are counted once, one report per selected folder
    that is not inside another, a symbolic link to a risky folder is risky;
  - dialogs: when a number is required only the right one confirms, yes/no dialogs default
    to Cancel, the focus starts on Cancel, Enter alone and closing the window cancel, a wrong
    number does not confirm, every selected folder with its count, the total and the
    operation are shown; a fake dialog helper placed first in `PATH` is not used, and a
    folder name with quotes or script code is shown as text, never run.

  How confirmed runs are tested without a bypass: the public confirmation has two
  constructors only, terminal and dialog, which take no input source: they open the terminal
  or the dialog themselves and check `IsTerminal` inside. The core that turns answers into a
  `ConfirmedPlan` is `pub(crate)`; the test answer source is a `#[cfg(test)]` item that calls
  it, so it exists only in the library's own unit tests (`tests/*.rs` cannot see it) and the
  compiler enforces R31. Cases that need confirmed writes (file appearing between plan and
  write, disk full) are library unit tests or pseudo-terminal tests; the folder-snapshot
  helper serves both. The executable is tested end to end under a pseudo-terminal (Unix pty,
  Windows ConPTY) and for its refusals; the dialogs through the OS accessibility interface
  where it can be driven, by hand otherwise (R39). There is no environment variable, hidden
  option or build flag that confirms.

### European trusted lists
Signatures may come from any country on the LOTL (Italy, Romania, France...). Trust is anchored in
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
  otherwise downloaded. The write plan (R29) and the report name them, for example "signatures
  from 3 countries: Italy, Romania, France; lists: Italy and France up to date, Romania
  downloaded now".
- R46. **Settable.** `--trust-lists auto` (default) / `all` / `it,ro,fr`; `--trust-list <file>`
  loads a list by hand; `--offline` uses only the embedded copies and the cache. A missing list
  is reported as such ("list of Romania not available offline"), never as an invalid signature.
- R47. **Cache.** Lists (and the CRLs of R49) are cached in the SignSpector cache folder and
  refreshed when their own `NextUpdate` date passes; `uninstall` removes the cache (R40). The
  cache folder is the operating system's standard one (R42); no option moves it. Tests move it
  only through the system's own variables (`HOME`, `XDG_CACHE_HOME`; Windows: to decide, see
  after R42). The tool replaces only files under the names it derives itself: one fixed name
  per list, and for a CRL the SHA-256 of its CA certificate, never text taken from the input.
  It never replaces another file found in that folder, never follows a symbolic link there,
  and refreshes a file as R31 says (temporary file, then rename).
- R48. **Verdicts.** Qualified status is checked at the reference time (R9) using the service
  history in the list (a service withdrawn later still validates an earlier signature). A
  certifier on no list is reported as "not on a European trusted list", distinct from "invalid
  signature". Any country listed in the official LOTL is accepted, the United Kingdom included.
  The report names every list used (country, sequence number, issue date).
- Cost: verifying XAdES needs XML canonicalisation (exclusive C14N) and XML signature
  verification; no mature pure-Rust library exists, so it is written here, test first, as
  carefully as the BER reader.
- R49. **Revocation without a query per signature.** Network traffic grows with the number of
  certificates, never with the number of files: one result per certificate, the same
  certificate in a thousand files is checked once; a CRL is fetched at most once per CA per
  run.
  - **Reference time**: the proved time of R9 (a time stamp), otherwise the time of the check.
  - **Revocation data inside the signature** (CAdES -LT/-LTA) is used only if its own
    signature verifies against the issuing CA or an authorised OCSP responder and it was
    issued after the reference time; otherwise it is ignored and the CA's CRL is used.
  - **The CA's CRL**: fetched only once the chain reaches a CA of a trusted list, from its
    distribution point, `http` or `https` only (redirects too), with limits on size and time;
    its signature and issuer are verified before it is used or cached. It answers when it was
    issued after the reference time; when the reference time is the time of the check, a CRL
    inside its validity (`thisUpdate` <= now < `nextUpdate`) answers. Cached in the
    SignSpector cache folder until its `nextUpdate` (R47; removed by `uninstall`, R40). OCSP
    only when the CA publishes no CRL.
  - **Verdicts**:
    - "not revoked";
    - "revoked on <date>", before a proved reference time (a time stamp): invalid;
    - "revoked on <date>", after the time stamp: valid when signed, and the report shows the
      revocation date;
    - revoked, but the signature has no time stamp: "cannot be determined: no proof the
      signature is older than the revocation" (as ETSI EN 319 102-1), never "invalid";
    - "cannot be determined" also when the certificate has expired and the CRL no longer
      lists expired certificates (a CRL answers for an expired certificate only if issued
      before its `notAfter` or marked ExpiredCertsOnCRL), and for a suspension
      (`certificateHold`) that a later CRL no longer shows;
    - "revocation not checked": no network, or no CRL fresh enough could be fetched.
    None of the last three is "invalid signature". `--offline` uses a cached CRL that still
    answers, otherwise "revocation not checked".

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
- R38. **Context menu and dialogs**: only native OS menus and native dialogs, which inherit
  the OS accessibility (screen readers, keyboard); clear labels in the user's language. The
  dialogs ask the confirmations of R30 for runs started from the context menu. No
  custom-drawn GUI, no PowerShell.
- R39. **Verification.** Automated: unit tests on the HTML structure (lang, headings, table
  headers, no colour-only status) and an accessibility checker on sample reports in CI (e.g.
  `axe-core` or `pa11y`); console tests with `NO_COLOR` and `--plain`. Manual before each
  release: NVDA on Windows, VoiceOver on macOS, Orca on Linux, keyboard only, 200% zoom,
  Windows high contrast. Results recorded in `docs/accessibility.md`.

### Uninstalling
- R40. **`signspector uninstall`** removes everything SignSpector added to the system, and only
  that: context menu entries, the Windows "Installed apps" entry (R42), trust-list and CRL cache,
  the install manifest (R41). SignSpector saves no preferences and keeps no log files: the
  record of written documents is in the report (R33). Same rule as every command that changes
  something (R19): it shows the exact list of what it would remove and removes it after a yes/no
  question; never from a script (R30); accessible like the rest (R35).
- R41. **Only what we installed.** `install-menu` records every item it creates (path or
  registry key, plus a hash of the content) in a manifest in the SignSpector config folder;
  `uninstall` removes only manifest items that still match, reports changed or foreign items
  and leaves them. If the manifest is lost, entries are recognised by an explicit SignSpector
  marker, never by guessing. Running it twice is harmless. Each item is created with
  `create_new` (on Windows: a registry key created only if it did not exist; Q1 below). An
  item is foreign when it is not in the manifest and has no SignSpector marker. When a foreign
  item has the same name, `install-menu` reports it and leaves it, and it never enters the
  manifest. So `uninstall` never removes it (owner's decision, 2026-11-23). An item of ours
  that already exists (in the manifest, or marked after a lost manifest) is left as it is if
  unchanged, and reported if changed. `install-menu` and `uninstall-menu` are the only commands
  that replace the manifest; `uninstall` removes it (R40).
- R42. **Per platform.**
  - Windows: per-user, no admin: registry keys under `HKCU`, plus an uninstall entry in
    `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\SignSpector` so the user finds it
    in Settings -> Apps; its `UninstallString` runs `signspector.exe uninstall --interactive`,
    which shows the list in a native dialog with the focus on Cancel (R30).
    A running `.exe` cannot delete itself: the tool says where it is so the user can delete it
    (no PowerShell, no scheduled tricks).
  - macOS: Quick Actions in `~/Library/Services`, caches in `~/Library/Caches/SignSpector`,
    the manifest in `~/Library/Application Support/SignSpector`.
  - Linux: Nautilus script, Dolphin service menu, the cache in `~/.cache/signspector`, the
    manifest in `~/.config/signspector`. `.deb`/`.rpm` remove only system files they installed; the
    per-user items are removed by `signspector uninstall` (the package's removal message
    says so).
- *To decide* (before roadmap 3.5): the Windows cache and manifest folders, and how the tool
  finds them so that tests can move them. The candidate crate `directories` asks the system
  (`SHGetKnownFolderPath`) and ignores `LOCALAPPDATA`, so the test rule of R47 cannot work with
  it as is (audit 0007, F2). Tests of `install-menu` must also move the manifest folder
  (`XDG_CONFIG_HOME`, `APPDATA`).
- *To decide* (before roadmap 5.1): Q1, how `create_new` applies to a registry key (for
  example `RegCreateKeyEx`, accepted only when the key was created new, also for the
  `Uninstall\SignSpector` key) and to a macOS Quick Action, which is a `.workflow` folder.
- *To decide* (before roadmap 5.3): whether `uninstall` removes a file in the cache folder that
  the tool did not write, or leaves and lists it (R40, R43).
- R43. **User data is never removed**: originals, extracted documents and reports stay; at
  the end the tool lists what it left in place on purpose and where the executable is.

## Architecture (proposal)

Library crate with one module per concern, the executable only parses arguments and prints:

| Module | Role | Candidate crates |
|---|---|---|
| `names` | portable file names, collision keys, free names (R32, R17) | `unicode-normalization` |
| `i18n` | translation layer, language choice (R27) | to decide (1.4) |
| `confirm` | counts, questions, answers (typed count or yes/no), `ConfirmedPlan` (R28–R30) | `std::io::IsTerminal` |
| `ber` | BER/DER reader, indefinite lengths, own code (RustCrypto `der` is DER-only) | none |
| `cms` | SignedData, signer infos, attributes, countersignatures | `ber` |
| `tsp` | RFC 3161 tokens, RFC 5544 `.tsd`, `.m7m` | `cms` |
| `crypto` | digests and signature checks | `sha1`, `sha2`, `rsa`, `p256`, `p384`, `p521`, `ecdsa` |
| `x509` | certificates, names, extensions, chain building, revocation (R49) | `x509-parser` |
| `xmldsig` | exclusive C14N, XML signature verification (R44) | `roxmltree`, own code |
| `tsl` | LOTL and national lists: embedded copies, choice by country, refresh, cache (R44–R48) | `roxmltree`, `flate2`, `ureq` + rustls, `directories` |
| `scan` | folder walk, per-file pipeline, parallelism | `std::thread::scope` |
| `extract` | safe writer, record of written documents in the report, `undo` (R31, R33), content type (R18) | `zip` |
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
- Brainpool curves, AIA download of missing intermediates: needed by the real files?
- Native dialogs (R30, R38) before roadmap 5.2: a folder list, a text field for the number and
  the focus on Cancel. Windows has no stock dialog with a text field (MessageBox and
  TaskDialog have none): an own Win32 dialog in Rust, no PowerShell. macOS: AppleScript
  `display dialog` (text field, default button Cancel). Linux: `zenity` or `kdialog`, which
  may be missing; then a context-menu run refuses (R19). Which crate or code per OS?
  Whatever is chosen: helper programs are run from fixed system paths (`/usr/bin/osascript`,
  `/usr/bin/zenity`...), never found through `PATH`; folder names reach them as arguments,
  never spliced into AppleScript source or markup. Enter in the number field confirms only if
  the number is right; otherwise it does nothing. Several folders selected in Windows
  Explorer start one process each with plain registry verbs: one summary needs a
  multi-selection entry (`IExecuteCommand`, a drop target, or one instance collecting the
  others).
- Pseudo-terminal tests (R34) need a pty crate as a dev-dependency, accepted by `deny.toml`:
  which one, for Unix and Windows ConPTY?

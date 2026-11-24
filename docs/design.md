# SignSpector: requirements and design

Status: draft, completed with the owner step by step. Open points are listed at the end, under
"What is still open?", each with the roadmap step that needs the answer.

Each rule is written once, in one requirement. Other places name that requirement in brackets
(R31) instead of repeating the rule.

## What is SignSpector for?

It saves opening signed files one by one. Offices receive and archive documents signed
digitally (CAdES `.p7m`, detached `.p7s`) and time-stamped (`.tsd`, `.m7m`). They are often
nested: a `.p7m` inside a `.p7m`, a `.tsd` around a `.p7m`. Opening them one by one is slow and
tells little about the signatures.

SignSpector takes a folder and finds every such file. It opens all the layers and checks
signatures, certificates and time stamps. Then it writes a report anyone can read. On request it
saves the signed documents beside the originals, ready to open.

## What must it do?

### Which files does it look at?
- R1a. A name is an envelope when its extension is `.p7m`, `.p7s`, `.tsd` or `.m7m`, in any
  letter case. The test is on the name only, and any bytes are allowed in the rest of the name
  (non-UTF-8 names on Linux). *(done: `is_envelope`)*
- R1b. The folder is walked recursively. Only regular files are tested with R1a: a folder named
  `archivio.p7m` is not an envelope.
- R2. Some entries are not walked or not checked, and each is listed in the report, so nothing
  is left out silently:
  - an unreadable folder is reported and skipped, and the walk goes on;
  - a symbolic link met during the walk, to a file or to a folder, is not followed (a selected
    folder is different: R19);
  - a hidden folder (name starting with `.`) is skipped.

### How does it open an envelope?
- R3. It reads CMS SignedData in BER, including indefinite lengths (common in real files), and
  in base64 form.
- R4. It unwraps nested layers until the signed document is reached, and reports each layer.
- R5. It reads RFC 5544 TimeStampedData (`.tsd`) and `.m7m` (MIME with signature and time
  stamp).
- R6. For a detached `.p7s`, it looks for the signed file beside it.
- R7. A malformed file never stops the run. It becomes a "problem" line for that file (source
  text in English, translated per R27).

### What does it verify?
- R8. Each signature: the digest of the content, the signed attributes, and the signature (RSA
  PKCS#1 v1.5, RSA-PSS, ECDSA P-256/P-384/P-521; SHA-1/256/384/512).
- R9. The signer's certificate: validity at the reference time, key usage (non-repudiation),
  qualified and QSCD flags.
  - The reference time is a proved time only: the signature's time stamp, or the time stamp
    of a `.tsd` or `.m7m` that contains the file (R5, R12).
  - The signing-time attribute is written by the signer and proves nothing. Without a time
    stamp, the reference time is the time of the check, and the report shows the claimed time
    marked "claimed, not proved".
  - R48 and R49 use the same reference time.
- R10. The chain must reach a CA of a European trusted list (R44–R48): the national list of
  the certifier's country, reached through the EU List of Trusted Lists. Optionally it may reach
  the system trust store, labelled "recognised by the system" (translated per R27).
- R11. Countersignatures.
- R12. Time stamps (RFC 3161): the imprint matches, and the TSA signature and chain are valid.
- Revocation is R49.

### What does it show and write after an analysis?
- R13. A console summary per file, in the user's language (R27), with colours (R35). Exit codes:
  0 all fine, 1 problems found, 2 cannot run.
- R14. An HTML report (one self-contained file) in each analysed folder, covering that folder
  only. With `--report <file>`, one file for the whole run instead. `--no-report` skips it;
  R16 says when it does not apply.
- R15. With `--json <file>`, a JSON file with the same information, for scripts.
- R16. **What each command writes.**
  - `check` (the default) writes no document. It writes only the HTML report (R14), the JSON
    file (R15) and the tool's own cache of trusted lists and CRLs (R47).
  - `extract` writes the signed documents beside the originals (`Relazione.pdf.p7m` ->
    `Relazione.pdf`) after the two confirmations of R28 and R29. Typing the number of documents
    is the safeguard.
  - An extraction always writes its own report, and its JSON file when `--json` is given, so
    that `undo` has the list of documents (R33). `--no-report` does not apply to it (owner's
    decision, 2026-11-23).
  - A `check` run writes documents in one case only: an extraction chosen at the interactive
    end of run (R20), which goes through R29.
  - How every file is created, and which files may ever be replaced, is R31.

### How does it name extracted documents?
- R17. Never overwrite. The same content already there: nothing to do. Different content:
  `Relazione (1).pdf`. Originals are never modified, moved or renamed.
- R18. A name without a usable extension gets one guessed from the content (PDF, ZIP-based
  office formats, XML, images).
- R32 has the rules for valid names.

### How is it used?
- R19. **Command line.** Commands: `check <dir>...` (default), `extract <dir>...`,
  `undo <report>`, `install-menu`, `uninstall-menu`, `uninstall`. There is no `--apply`,
  `--yes` or `--expect`.
  - Every command that changes files or the system shows the exact plan first and acts only
    after a person confirms. How a person confirms, at a terminal, in a dialog or not at all
    from a script, is R30. The one exception: `check` in an ordinary run from a script writes
    its report (HTML and JSON) and the cache with no question (R16, R30).
  - A number is typed only for files found in a folder: the files to process in a risky run
    (R28) and the documents to write (R29). `undo`, `install-menu`, `uninstall-menu` and
    `uninstall` change only what the tool itself made, and ask a yes/no question (R30).
  - Several folders. `check` and `extract` take one or more folders (several can be
    selected in the file manager). They are counted and confirmed together:
    - one summary with a row per folder (path, number of files to process, number of files of
      any kind) and the totals, and one question for all. The number typed is the total;
    - when the run is risky (R28), the summary says why: the kind of sensitive folder, or the
      10,000-file limit;
    - a folder with no envelopes is shown with 0; if all are empty, the run stops;
    - the same folder given twice (also spelt differently: letter case, a symbolic link, a
      trailing slash), or a folder inside another selected one, is counted once, under the
      outer folder. The summary says so, and its envelopes go in the outer folder's report;
    - a selected folder that is a symbolic link is resolved, then counted and judged like any
      other folder (R28).
  - `--interactive` says that a person is there even without a terminal: questions come in
    native dialogs (R30) and the run ends with the interactive end of run (R20). The
    context-menu entries and the Windows uninstall entry (R42) pass it. With a terminal, the
    questions stay in the terminal and R20 still applies. If no dialog can be shown (no
    desktop session), `--interactive` refuses with exit code 2, like a script.
  - `--plan` shows what the command would do and stops before doing it. It writes nothing,
    not even the report or the cache, and downloads nothing: it uses the embedded lists and
    those already in the cache.
    - `check --plan` only counts (R28; no envelope is opened) and prints the summary. It asks
      no question and runs everywhere (R30).
    - `extract --plan` builds the write plan of R29, which opens every envelope. So it asks the
      R28 question first, and from a script it behaves like `check` (R30). It also says which
      trusted lists a real run would download (R45).
    - For the other commands it lists the items, with no question (R30).
  - Options: `--open`, `--report`, `--no-report`, `--report-lang <code>`, `--json <file>`,
    `--threads`, `--offline`, `--trust-lists <auto|all|codes>`, `--trust-list <file>`,
    `--lang <code>`, `--interactive`, `--plain`, `--no-color`, `--plan`. Help is translated
    (R27).
- R20. **Interactive end of run** (double-click on Windows, context menu, `--interactive`).
  After the analysis, the tool offers to view the report or to extract. An extraction goes
  through the write plan and its confirmation (R29) and reuses the analysis already done.
  - The first report is never rewritten. The extraction writes a second report beside it (next
    free name, R31) with the analysis and the documents written, and `undo` uses that one (R33).
  - With `--json`, it also writes a second JSON file beside the first.
  - After `check --no-report` there is no first report: the extraction report is the only one.
- R21. `install-menu` and `uninstall-menu` (plan, R19; yes/no question, R30) add and remove the
  file manager's context menu: Windows per-user registry keys (no admin, no PowerShell), macOS
  Quick Actions, a Linux Nautilus script and Dolphin service menu. Full removal: `uninstall`
  (R40–R43).

### How is it built and released?
- R22. One self-contained executable per platform, with pure Rust dependencies.
- R23. Files are processed in parallel, and the output is printed in a stable order.
- R24. Targets: Windows x86_64, macOS arm64 + universal, Linux x86_64 static (musl).
- R25. Linux packages: `.deb`, `.rpm` and a generic `.tar.gz` (static musl binary, works on any
  distribution). They are built on the Mac from the musl binary with `cargo-deb` and
  `cargo-generate-rpm` (pure Rust, no dpkg or rpmbuild needed).
- R26. Versioning: SemVer starting from `0.1.0`. `0.x` while behaviour and options may still
  change; `1.0.0` when the tool is ready to replace the old one in production. The old tool's
  numbering is not continued. Every release is a git tag `vX.Y.Z`.

### Which languages does it speak?
- R27. The interface is translated: console messages, `--help`, HTML report, JSON field values
  meant for people, user guide.
  - The language is the one chosen with `--lang it`, otherwise the operating system's language,
    otherwise English.
  - No preference is saved. A command to save one can be added later, with its plan and
    question (R30).
  - Source language English; first translation Italian; more can be added without code
    changes.
  - The report is written in the interface language by default. `--report-lang <code>` writes it
    in another one, for example to send it to an office abroad.

### How does it protect the user's files?
No folder is processed right after a person chooses it: the tool counts first and asks (R28).
No document is written without a second, separate confirmation on the full write plan (R29).
There is never an implicit yes: R30 says how each kind of run confirms, and what runs from a
script. R31 says how every file is created and which files may ever be replaced.

- R28. **Confirm before analysing.** After the folders are chosen, the tool only counts (no
  envelope is opened) and asks a yes/no question (R30).
  - The question shows: folder, number of files to process (the envelopes, R1a), number of
    files of any kind, total size, number of subfolders, unreadable folders that will be
    skipped. The interface calls the envelopes "files to process". Zero envelopes: it says so and
    stops.
  - A risky run gets a stronger warning, and the user must type the number of files to process. A
    run is risky when one chosen folder is a sensitive folder: the root of a drive or volume, the
    user's home, Desktop, Documents, a system folder (`C:\Windows`, `Program Files`, `/System`,
    `/usr`, `/etc`...) or a network share root. It is also risky when the folders hold more than
    10,000 files of any kind in all, subfolders included (owner's decision, 2026-11-23). A run
    that is not risky is an ordinary run. "Risky" and "ordinary" always describe the whole run,
    never one folder.
  - The 10,000 count covers the regular files of the folders the walk visits (R2). Files in
    hidden folders, behind symbolic links met during the walk, or in unreadable folders are not
    counted. A file in overlapping folders counts once.
  - Each kind of sensitive folder is judged on the path after resolving symbolic links.
- R29. **Confirm before writing.** An extraction first builds the complete write plan and shows
  it: new documents, documents already present with identical content (not rewritten),
  documents saved under an alternative name `x (1).pdf`, and "existing files modified: 0"
  (always zero, shown as a guarantee). The full list can be viewed. To proceed, the user types
  the number of documents to write (language-neutral, cannot be confirmed by a stray key).
- R30. **Three ways to confirm, never an implicit yes.**
  - Terminal (`std::io::IsTerminal` on input and output): questions in the console (R19, R28,
    R29). "Terminal" means both input and output are a terminal. With output redirected
    (`| tee log`, `> file`) the run counts as a script. Yes/no questions default to No, and
    Enter alone cancels. A typed number confirms only if it is the right one. Any other answer
    (a wrong number, `y`, `n`, Enter alone) never confirms. This holds for the files to process
    of a risky run (R28) and for the documents to write (R29). The owner decided on 2026-11-23
    that only the right number confirms and that any other answer never confirms. The answers
    and the default are written out in words in the user's language (R35, R27).
  - Context menu (no terminal, started with `--interactive`): the same confirmations, with the
    same number to type and the same default, in a native dialog (R38), with a shorter summary
    than the console.
    - The dialog lists every selected folder with its number of files to process (envelopes to
      analyse, R28; documents to write, R29), the total, the reason when the run is risky
      (R19) and the operation proposed. Then it asks the question.
    - When a number is required (risky run, R28; R29), it is typed in a text field, and Confirm
      accepts only the right number. Otherwise the dialog is a yes/no question.
    - In every dialog the focus starts on Cancel. Enter alone and closing the window cancel.
      There is no time limit.
  - Script (no terminal, no `--interactive`): `extract`, `undo`, `install-menu`,
    `uninstall-menu`, `uninstall`, and `check` in a risky run (R28) stop with exit code 2,
    write nothing, and say that a person must confirm. A `y` or a number arriving on a pipe is
    not a confirmation. Only these run: `check` in an ordinary run, `check --plan` (also in a
    risky run), `extract --plan` in an ordinary run, and `--plan` of `undo`, the menus and
    `uninstall` (a list).
- R31. **Never overwrite, never write outside.** This is the one place for these rules.
  - In code, writing a document requires a `ConfirmedPlan` that only the confirmation step can
    build (typestate): a path that writes without confirmation does not compile. Originals are
    held in a read-only `Original` type that write functions do not accept.
  - Every file the tool writes is created with `OpenOptions::create_new(true)`: documents,
    reports, JSON files, menu items and temporary files. The OS refuses if the name exists, even
    if the file appeared after the plan. A cache file and the manifest are created that way under
    a temporary name, and reach their own name only by the rename described below, also the
    first time.
  - When the name is taken: a document, report or JSON file takes the next free name (`(1)`,
    `(2)`...); a menu item is reported and left (R41). How this applies to registry keys and
    `.workflow` folders is still open (question "Before 5.1").
  - Only two kinds of file are ever replaced: the tool's own cache files (R47) and its
    install manifest (R41). They are replaced in two steps. The new content is written with
    `create_new` under a temporary name in the same folder; then that file is renamed over the
    old one. The tool never follows a symbolic link there, and it refuses a name that exists and
    is not a regular file. Nothing is ever written in place.
  - A partly written file (error, disk full) is removed, only if the tool created it.
  - Before writing, each original is re-checked against the analysis (size, mtime, SHA-256). If
    the folder changed, the plan is rebuilt and confirmed again.
  - Every document must stay inside the selected folder its envelope was found in, after
    resolving `..` and symbolic links.
  - Free disk space is checked before starting. Ctrl+C finishes the current file, stops, and the
    report records what was done.
- R32. **Portable file names.** Names taken from envelopes (and the `(n)` variants) must be
  valid on Windows, macOS and Linux at the same time, and on FAT32 and exFAT, whatever
  system the tool runs on (archives move between systems):
  - removed or replaced: `/` `\` `:` `*` `?` `"` `<` `>` `|`, NUL and control characters
    U+0000–U+001F and U+007F; trailing dots and spaces; leading spaces;
  - reserved Windows names, with or without extension and in any case: `CON`, `PRN`, `AUX`,
    `NUL`, `COM0`–`COM9`, `LPT0`–`LPT9` (also with superscript digits `¹²³`);
  - leading `-` (taken as an option by shell commands) and leading `.` (hidden on macOS and
    Linux) are neutralised; `.` and `..` are never names;
  - invalid UTF-8 or unpaired surrogates are replaced; names are stored in Unicode NFC;
  - length: at most 255 UTF-8 bytes and 255 UTF-16 units per component, cut without breaking
    a character or the extension;
  - collisions are checked case-insensitively and normalization-insensitively (NTFS and the
    APFS default are case-insensitive; APFS treats NFC and NFD as the same name), so two
    documents never compete for names that the file system sees as equal;
  - the original name, when changed, is shown in the report.
- R33. **Undo.** The report written by an extraction records every document written, with its
  SHA-256 (R16, R20). `signspector undo <report>` removes only files written by SignSpector
  whose content still matches that hash. Changed or missing files are listed and left alone;
  originals are never touched. It shows what it would remove and removes it after a yes/no
  question (R30); never from a script. On a report that records no document it removes
  nothing and says so.
- R34. **Proof by tests.** A shared test helper snapshots the whole folder (paths and SHA-256)
  before and after every end-to-end test: originals identical, nothing changed but the
  confirmed plan.
  - Writing and undo (R29, R31, R32, R33): at the count of documents (R29), an empty answer,
    `y`, `n` or a wrong number writes nothing. At the `undo` question, an empty answer or `n`
    removes nothing. Also tested:
    - a file appearing between plan and write;
    - names with `..`, reserved names, forbidden characters, NFC/NFD and case collisions,
      over-long names;
    - a symbolic link pointing outside;
    - disk full (simulated);
    - `undo` with a modified file, and `undo` on a report that records no document.
  - Risky run at the terminal (R28, R30): an empty answer, `y`, `n` or a wrong number starts
    no analysis.
  - Scripts (R30): every changing command, `check` and `extract --plan` in a risky run, and
    `--interactive` without a desktop are refused with exit 2. `check` in an ordinary run,
    `check --plan` in any run, `extract --plan` in an ordinary run and `--plan` of `undo`, the
    menus and `uninstall` run without a question. Output redirected counts as a script.
    `--interactive` with a terminal keeps the questions in the terminal.
  - `--plan` (R19): it writes nothing, not even the report or the cache, and downloads nothing;
    `extract --plan` names the lists a real run would download.
  - What `check` writes (R16): only its report is added to the folder, and nothing with
    `--no-report`. An existing report or JSON file, also one named with `--report` or `--json`,
    is not replaced: the new one gets the next free name.
  - Extraction reports (R16, R20, R33): at the interactive end of run, documents are written
    only through R29: any answer other than the right number writes none (R30), and declining
    writes none. An extraction there writes a second report, and with `--json` a second JSON
    file, without touching the first. `undo` on the second report removes the documents.
    `extract --no-report`, with and without `--json f`, follows the open question on it
    ("Before 4.4"): either it writes the extraction report (and `f`), or it is refused with
    exit 2 and writes nothing.
  - Cache and manifest (R31, R47): end-to-end tests point the cache to a temporary folder,
    never the user's real one. A file in the cache folder under a name the tool does not derive
    is never replaced. A symbolic link, a folder or another non-regular file at one of the
    tool's own names (cache or manifest) is refused, never followed. A CA whose name holds
    `../` or a separator gives a cache file named only by the hash, inside the folder.
    Snapshots of the config and cache folders around `install-menu`, `uninstall-menu` and a list
    refresh show that only the manifest and the cache files changed.
  - Menu items (R41): `install-menu` run twice changes nothing. A foreign item with the same name
    is reported, left, never enters the manifest, and `uninstall` does not remove it. After a
    lost manifest, our marked items are recognised.
  - Counting (R19, R28): the summary shows both counts in each row and in the totals, and the
    reason for a risky run; the dialog shows the reason. More than 10,000 files of any kind
    (subfolders included) is risky even with few envelopes, and the number typed is the files to
    process: exactly 10,000 is not risky, 10,001 is, also as a total over several folders. Files
    in hidden folders, behind symbolic links met during the walk or in unreadable folders are not
    counted; a selected folder that is a symbolic link is resolved and counted; overlaps count
    once.
  - Several folders (R19, R28): the total is typed. One sensitive folder makes the whole run
    risky. All folders empty stop the run. Overlaps (also by letter case, symbolic link,
    trailing slash) are counted once. There is one report per selected folder that is not inside
    another. Each kind of sensitive folder makes the run risky, selected directly or through a
    symbolic link (owner's decision, 2026-11-24).
  - Time (R9): a back-dated signing-time attribute changes no verdict; without a time stamp the
    report says "claimed, not proved".
  - Yes/no questions (R30): Enter alone and `n` cancel, `y` on a pipe is refused, a number is
    not a yes.
  - Dialogs (R30, R38):
    - when a number is required, only the right one confirms;
    - a wrong number does not confirm;
    - yes/no dialogs default to Cancel;
    - in every dialog the focus starts on Cancel;
    - Enter alone and closing the window cancel;
    - every selected folder with its count, the total and the operation are shown;
    - a fake dialog helper placed first in `PATH` is not used;
    - a folder name with quotes or script code is shown as text, never run.

  How are confirmed runs tested without a bypass? The public confirmation has two constructors
  only, terminal and dialog, which take no input source: they open the terminal or the dialog
  themselves and check `IsTerminal` inside. The core that turns answers into a `ConfirmedPlan`
  is `pub(crate)`. The test answer source is a `#[cfg(test)]` item that calls it, so it exists
  only in the library's own unit tests (`tests/*.rs` cannot see it), and the compiler enforces
  R31. Cases that need confirmed writes (a file appearing between plan and write, disk full)
  are library unit tests or pseudo-terminal tests; the folder-snapshot helper serves both. The
  executable is tested end to end under a pseudo-terminal (Unix pty, Windows ConPTY) and for
  its refusals. The dialogs are tested through the OS accessibility interface where it can be
  driven, by hand otherwise (R39). There is no environment variable, hidden option or build
  flag that confirms.

### Which trusted lists does it use?
Signatures may come from any country on the EU List of Trusted Lists (LOTL,
`https://ec.europa.eu/tools/lotl/eu-lotl.xml`, signed by the European Commission): Italy,
Romania, France and the others. The LOTL points to each national trusted list and names the
certificates that sign it. Checked on 2026-11-22: LOTL no. 398, 43 pointers (EU-27, Iceland,
Liechtenstein, Norway, United Kingdom).

- R44. **Chain of trust.** The executable embeds the LOTL and the Commission's LOTL signing
  certificates (published in the Official Journal of the EU).
  - The LOTL is used only if it verifies against the embedded Commission certificates.
  - A national list is used only if its XAdES signature verifies against the certificates the
    LOTL names for that country. Italy is one country among the others.
  - The repository stores no trusted list. The release build downloads the current LOTL and the
    Italian list and embeds them, so the tool works offline out of the box. At the first run with
    network the tool refreshes them into its cache (R47).
  - XAdES needs XML canonicalisation (exclusive C14N) and XML signature verification. No mature
    pure-Rust library exists, so we write it here, test first, as carefully as the BER reader.
- R45. **Automatic choice.** The analysis collects the country of every certifier found in the
  files (`C=` of the issuing CA) and loads only those lists: from the cache if still valid,
  otherwise downloaded. The write plan (R29) and the report name them, for example "signatures
  from 3 countries: Italy, Romania, France; lists: Italy and France up to date, Romania
  downloaded now".
- R46. **Settable.** `--trust-lists auto` (default), `all` or `it,ro,fr`. `--trust-list <file>`
  loads a list by hand. `--offline` uses only the embedded copies and the cache. A missing list
  is reported as such ("list of Romania not available offline"), never as an invalid signature.
- R47. **Cache.** This is the one place for the cache rules.
  - Lists, and the CRLs of R49, are cached in the SignSpector cache folder and refreshed when
    their own `NextUpdate` date passes. A cached list that verifies (R44) takes precedence over
    the embedded copy. Removing the cache is R40.
  - The cache folder is the operating system's standard one (R42); no option moves it. Tests move
    it only through the system's own variables (`HOME`, `XDG_CACHE_HOME`; Windows: question
    "Before 3.5", open).
  - The tool uses only names it derives itself: one fixed name per list, and for a CRL the
    SHA-256 of its CA certificate (partitioned CRLs: question "Before 3.9"). A name is never text
    taken from the input.
  - It never replaces another file found in that folder. A cache file is replaced only as R31
    says: a new file, a rename, no symbolic link.
- R48. **Verdicts.** Qualified status is checked at the reference time (R9) using the service
  history in the list: a service withdrawn later still validates an earlier signature. A
  certifier on no list is reported as "not on a European trusted list", distinct from "invalid
  signature". Any country listed in the official LOTL is accepted, the United Kingdom included.
  The report names every list used (country, sequence number, issue date).
- R49. **Revocation without a query per signature.** Network traffic grows with the number of
  certificates, never with the number of files. There is one result per certificate: the same
  certificate in a thousand files is checked once. A CRL is fetched at most once per CA per
  run (partitioned CRLs: question "Before 3.9").
  - The reference time is the proved time of R9 (a time stamp), otherwise the time of the
    check.
  - Revocation data inside the signature (CAdES -LT/-LTA) is used only if its own signature
    verifies against the issuing CA or an authorised OCSP responder, and it was issued after
    the reference time. Otherwise it is ignored and the CA's CRL is used.
  - The CA's CRL is fetched only once the chain reaches a CA of a trusted list. It comes
    from its distribution point, `http` or `https` only (redirects too), with limits on size and
    time. Its signature and issuer are verified before it is used or cached. It answers when it
    was issued after the reference time. When the reference time is the time of the check, a
    CRL inside its validity (`thisUpdate` <= now < `nextUpdate`) answers. It is cached until its
    `nextUpdate` (R47). OCSP is used only when the CA publishes no CRL.
  - The verdicts are:
    - "not revoked";
    - "revoked on <date>", before a proved reference time (a time stamp): invalid;
    - "revoked on <date>", after the time stamp: valid when signed, and the report shows the
      revocation date;
    - revoked, but the signature has no time stamp: "cannot be determined: no proof the
      signature is older than the revocation" (as ETSI EN 319 102-1), never "invalid";
    - "cannot be determined" also when the certificate has expired and the CRL no longer lists
      expired certificates (a CRL answers for an expired certificate only if issued before its
      `notAfter` or marked ExpiredCertsOnCRL), and for a suspension (`certificateHold`) that a
      later CRL no longer shows;
    - "revocation not checked": no network, or no CRL fresh enough could be fetched.

    None of the last three is "invalid signature". `--offline` uses a cached CRL that still
    answers, otherwise "revocation not checked".

### Who must be able to use it, and how?
Legal frame (Italy and EU): Legge 4/2004 ("Legge Stanca", as amended by D.Lgs. 106/2018) and
the AgID guidelines on the accessibility of IT tools. They refer to the harmonised standard
EN 301 549 (ch. 11 software, ch. 12 documentation and support, ch. 9 web content = WCAG).
The European Accessibility Act (Directive 2019/882, D.Lgs. 82/2022) probably does not cover
this tool, but meeting EN 301 549 covers it too. Targets: EN 301 549 for the program and
WCAG 2.2 level AA for the HTML report and the user guide. Whoever deploys the tool in a
public administration checks the applicable obligations (for example an accessibility
statement).

- R35. **Console.**
  - Information is never conveyed by colour or symbols alone. Every status is a word ("OK",
    "Warning", "Error" in the user's language); colours only reinforce it, with sufficient
    contrast on both light and dark terminals, never red/green as the only difference. Colours
    are off with `NO_COLOR`, `--no-color`, or when output is not a terminal.
  - No box drawing, ASCII art or tables made of spaces for essential information: linear text,
    one fact per line, read well by NVDA, JAWS, Narrator, VoiceOver and Orca.
  - Progress does not flood screen readers: no spinners, no rewriting the same line many times
    a second. `--plain` (also `SIGNSPECTOR_PLAIN=1`) gives line-by-line output with a progress
    line at most every few seconds and a final summary.
  - Prompts: the full question on one line, with the possible answers and the default spelled
    out in words; keyboard only; no time limits on any prompt.
  - Messages in plain language. Every error says what happened, which file, and what the user
    can do.
- R36. **HTML report (WCAG 2.2 AA).**
  - `lang` set to the report language; a meaningful `<title>`; landmarks (`header`, `main`,
    `nav`) and a "skip to content" link; headings in order, no level skipped.
  - Real tables with `<caption>` and `<th scope>`. Status is shown as text (with an optional
    icon that has a text alternative), never by colour alone.
  - Contrast at least 4.5:1 for text and 3:1 for UI parts and icons, in light and dark mode
    (`prefers-color-scheme`); `prefers-reduced-motion` is respected.
  - Works at 200% zoom and reflows at 320 CSS px width without horizontal scrolling (except
    data tables, which scroll on their own).
  - Fully keyboard operable (`<details>` and `<summary>` for expandable parts), visible focus,
    no keyboard traps; works without JavaScript; descriptive link texts; prints readably.
- R37. **Documentation and help** (EN 301 549 ch. 12): `--help` and the user guide are plain text
  or HTML (no scanned or untagged PDF), translated, and include a section on the accessibility
  features (`--plain`, `--no-color`, keyboard use, screen readers).
- R38. **Context menu and dialogs**: only native OS menus and native dialogs, which inherit the
  OS accessibility (screen readers, keyboard), with clear labels in the user's language. The
  dialogs ask the confirmations of R30 for runs started from the context menu. No custom-drawn
  GUI, no PowerShell. Helper programs that show a dialog are run from fixed system paths
  (`/usr/bin/osascript`, `/usr/bin/zenity`...), never found through `PATH`. Folder names reach
  them as arguments, never spliced into script source or markup.
- R39. **Verification.** Automated: unit tests on the HTML structure (lang, headings, table
  headers, no colour-only status), an accessibility checker on sample reports in CI (for
  example `axe-core` or `pa11y`), and console tests with `NO_COLOR` and `--plain`. Manual
  before each release: NVDA on Windows, VoiceOver on macOS, Orca on Linux, keyboard only, 200%
  zoom, Windows high contrast. Results are recorded in `docs/accessibility.md`.

### How is it uninstalled?
- R40. **`signspector uninstall`** removes everything SignSpector added to the system, and only
  that: context menu entries, the Windows "Installed apps" entry (R42), the trust-list and CRL
  cache, and the install manifest (R41). SignSpector saves no preferences and keeps no log
  files; the record of written documents is in the report (R33). As every command that changes
  something (R19), it shows the exact list of what it would remove and removes it after a
  yes/no question; never from a script (R30); accessible like the rest (R35).
- R41. **Only what we installed.**
  - `install-menu` records every item it creates (path or registry key, plus a hash of the
    content) in a manifest in the SignSpector config folder. `uninstall` removes only manifest
    items that still match; it reports changed or foreign items and leaves them.
  - If the manifest is lost, our items are recognised by an explicit SignSpector marker, never
    by guessing.
  - Each item is created as R31 says (registry keys and `.workflow` folders: still open,
    question "Before 5.1"). An item is foreign when it is not in the manifest and
    has no SignSpector marker. When a foreign item has the same name, `install-menu` reports it
    and leaves it, and it never enters the manifest, so `uninstall` never removes it (owner's
    decision, 2026-11-23).
  - An item of ours that already exists (in the manifest, or marked after a lost manifest) is
    left as it is if unchanged, and reported if changed.
    Running `install-menu` twice is harmless.
  - `install-menu` and `uninstall-menu` are the only commands that replace the manifest (R31);
    `uninstall` removes it (R40).
- R42. **Per platform.**
  - Windows: per-user, no admin. Registry keys under `HKCU`, plus an uninstall entry in
    `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\SignSpector`, so the user finds
    it in Settings -> Apps. Its `UninstallString` runs
    `signspector.exe uninstall --interactive`, which shows the list in a native dialog (R30). A
    running `.exe` cannot delete itself: the tool says where it is so the user can delete it
    (no PowerShell, no scheduled tricks). The cache and manifest folders: question "Before 3.5".
  - macOS: Quick Actions in `~/Library/Services`, the cache in `~/Library/Caches/SignSpector`,
    the manifest in `~/Library/Application Support/SignSpector`.
  - Linux: Nautilus script, Dolphin service menu, the cache in `~/.cache/signspector`, the
    manifest in `~/.config/signspector`. `.deb` and `.rpm` remove only system files they
    installed; the per-user items are removed by `signspector uninstall` (the package's removal
    message says so).
- R43. **User data is never removed**: originals, extracted documents and reports stay. At the
  end the tool lists what it left in place on purpose and where the executable is.

## How is the code organised?

A library crate with one module per concern; the executable only parses arguments and prints.
This is a proposal.

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

The order of work is in `roadmap.md`: safety-critical, pure parts first.

## Which test data do we use?

- Synthetic fixtures in `tests/fixtures/`, generated by a script (Homebrew `openssl@3`:
  `openssl cms -sign`, `openssl ts`) and by Rust test helpers for what OpenSSL cannot produce:
  BER indefinite lengths, nested envelopes, `.tsd`, base64, RSA-PSS, ECDSA, countersignatures,
  tampered content, expired and untrusted certificates, a fake TSL listing the test CA.
- Fuzzing of the `ber` and `cms` readers (`cargo fuzz`, needs nightly) once they exist: no
  input may panic or hang.
- Real documents stay on the Windows PC (`tests/corpus/`, git-ignored, personal data). They are
  used to check results by hand and, if useful, against the old tool's output.

## How do I build it on the Mac?

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
confirm that antivirus, SmartScreen and AppLocker accept a mingw-built executable.

## Which exceptions are recorded?

- Until the translation layer exists (roadmap 1.4), the placeholder message in `src/main.rs` is
  the only hard-coded user-facing text; it goes away with 1.4.

## What is still open?

The owner closed requirement changes in roadmap step 0.4 on 2026-11-23. Decisions on
requirements taken after that date are listed in the same step, each with its date. Each
question below is answered before the roadmap step named in its heading; that step points back
here.

### Before 1.4 (translations)
- Translation mechanism (for example Fluent `.ftl` files embedded in the executable, or
  `rust-i18n`), OS language detection (`sys-locale`), how dates and numbers are formatted per
  language.

### Before 1.5 (walk and count)
- A file named exactly `.p7m` (no stem) is not an envelope today: should the report list it as
  skipped? Are stand-alone time-stamp responses (`.tsr`) an input format?
- A selected folder whose name starts with `.`: is it analysed or skipped? Is the name judged
  after resolving the path (`check .`, `check ..`)? What about a selected folder inside a hidden
  one, and a selected symbolic link whose name is hidden but whose target is not, or the
  reverse?

### Before 1.6 (confirmation logic)
- R30 says any answer other than the right number never confirms. At the terminal, after such
  an answer (`y`, `n`, Enter, a wrong number), is the question asked again or does the run stop?
  Which exit code does a run declined at the terminal give? R13 has 0, 1 and 2, and R30 gives 2
  only for scripts.
- When is a typed number the right one? R29 calls it language-neutral. Does it accept the
  separators of the user's language (`12.345`, `12,345`), leading zeros, spaces around it (R27,
  questions "Before 1.4")? Is the answer the same for the dialog text field (R30, "Before 5.2")?

### Before 1.7 (safe writer) and the first pseudo-terminal test
- Pseudo-terminal tests (R34) need a pty crate as a dev-dependency, accepted by `deny.toml`:
  which one, for Unix and Windows ConPTY?
- R31 checks that a cache or manifest name is a regular file, then renames over it. What if the
  name changes between the check and the rename, or a foreign file appears at a name that did
  not exist yet (the first creation is also a rename) and would be replaced? How is that
  prevented?
- R31 keeps documents inside the selected folder. Does a rule cover a report written into a
  selected folder that is a symbolic link?

### Before 3.1 (crypto)
- Brainpool curves: are they needed by the real files?

### Before 3.2 (certificates)
- How does the report word a certificate expired at the time of the check, when no time stamp
  proves an earlier time?

### Before 3.5 (lists, download, cache)
- `ring` as the crypto provider of rustls (for the list refresh over HTTPS) contains C and
  assembly. It cross-compiles fine and is the only provider not banned in `deny.toml`
  (`aws-lc-rs` is). Do we accept it as an exception to "pure Rust", or look for a pure-Rust
  provider (for example `rustls-rustcrypto`)?
- Does the company proxy require integrated authentication (NTLM or Kerberos) to reach the
  trusted lists (`ec.europa.eu` for the LOTL, `eidas.agid.gov.it` and the other national
  addresses)? If yes, Windows needs WinHTTP for the refresh.
- Which folders hold the cache and the manifest on Windows, and how do tests move them? The
  candidate crate `directories` asks the system (`SHGetKnownFolderPath`) and ignores
  `LOCALAPPDATA` (audit 0007, F2), so the test rule of R47 cannot work with it as is. Tests of
  `install-menu` must also move the manifest folder; which variable does that on each OS is to
  be checked.
- When the tool refuses a cache name (R31), does the run go on with the list held in memory, or
  report "list not available"?
- What if the cache folder, or a folder above it, is a symbolic link (redirected profiles on
  company PCs)?
- Which non-regular files count as "not a regular file" at a cache or manifest name: a FIFO, a
  socket, a device, a Windows junction or reparse point?
- What is the fixed name of a national list? The territory code comes from the downloaded LOTL.
  The earlier draft accepted it only as two letters; the alternative is a hash. Which one? Is a
  list given with `--trust-list <file>` cached at all?
- How are temporary files named (R31), so that a leftover from an interrupted refresh does not
  block every later refresh? Is a temporary name one the tool derives (R47)?
- Certificates carry ISO country codes (`GR`, `GB`); the LOTL uses `EL` for Greece and `UK` for
  the United Kingdom (audit 0008, F4). How is a certificate's `C=` matched to a list, and which
  codes does `--trust-lists` accept?
- After an upgrade, the embedded LOTL may be newer than a cached one whose `NextUpdate` has not
  passed. Does the higher sequence number win over R47's precedence of the cache?
- Which event triggers the first refresh: the first run with network (R44) or a passed
  `NextUpdate` (R47)?
- Which limits on size and time apply to list downloads?

### Before 3.6 (chains)
- The download of missing intermediates (AIA): is it needed by the real files?
- R10 says the chain may optionally reach the system trust store. Which option turns it on?

### Before 3.7 (countersignatures and time stamps)
- Which time stamp counts when there are several?

### Before 3.9 (revocation)
- What is the verdict when the revocation time equals the time stamp? How are the revocation
  reasons `removeFromCRL` and `keyCompromise` treated? Settled together with the tests.
- Which values do the CRL limits on size and time take (R49)?
- A CA that publishes partitioned CRLs has several CRLs. Is each file named by the hash of the CA
  and of the distribution point, or is one kept? R47 and R49 change with the answer.

### Before 4.2 (HTML report)
- Layout and content of the report: do we start from the old tool's report as a sketch?
- Which accessibility checker runs in CI (R39: `axe-core`, `pa11y`, or another)?

### Before 4.4 (command line)
- What do `--open` and `--threads` do? (R23 asks for parallel work, not an option.)
- Is `extract --no-report` refused as a usage error (exit 2, nothing written), or accepted with a
  message saying that the extraction report is written anyway (R16)?
- How is a double-click on Windows detected (R20), and which folder does it analyse?

### Before 5.1 (install manifest)
- How does "created with `create_new`" (R31) apply to a registry key (for example
  `RegCreateKeyEx`, accepted only when the key was created new, also for the
  `Uninstall\SignSpector` key) and to a macOS Quick Action, which is a `.workflow` folder?
- An item of ours that matches the manifest but not what the current version would write (after
  an update or a moved executable): is it updated or reported? If updated, R31, R34 and the
  README change, since today a menu item is never replaced.
- After a lost manifest, what is a marked item compared with, and does it enter the new
  manifest?
- A symbolic link or a folder at the manifest path: `install-menu` should refuse before it
  creates any item; what do `uninstall-menu` and `uninstall` do there?
- How do tests move the Windows `HKCU` keys (the menu keys and the `Uninstall\SignSpector`
  key), which no variable moves, and how do the R34 snapshots cover them? Which variable moves
  the menu folders on macOS and Linux is to be checked.

### Before 5.2 (context menu and dialogs)
- R30 says Enter alone cancels a dialog. In a dialog number field, what does Enter do after the
  right number: confirm, or cancel because the focus is on Cancel? After a wrong number, does
  Enter do nothing (the dialog stays open) or cancel? The same question for Confirm after a
  wrong or empty number.
- What must the shorter dialog summary still show: unreadable folders, alternative names,
  "existing files modified: 0", a way to see the full list, and the list for `undo`, the menus
  and `uninstall`?
- Does the dialog of R30 also show the count of files of any kind, as the console summary does
  (R19)?
- Native dialogs (R30, R38) need a folder list, a text field for the number and the focus on
  Cancel. Windows has no stock dialog with a text field (MessageBox and TaskDialog have none):
  an own Win32 dialog in Rust, no PowerShell. macOS: AppleScript `display dialog` (text field,
  default button Cancel). Linux: `zenity` or `kdialog`, which may be missing; then a
  context-menu run refuses (R30). Which crate or code per OS? Whatever is chosen follows R38.
- Several folders selected in Windows Explorer start one process each with plain registry
  verbs. One summary needs a multi-selection entry (`IExecuteCommand`, a drop target, or one
  instance collecting the others).

### Before 5.3 (uninstall)
- Does `uninstall` remove a file in the cache folder that the tool did not write, or leave and
  list it (R40, R43)? Does it remove leftover temporary files (R31)?

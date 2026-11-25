# SignSpector

SignSpector checks signed and time-stamped files (`.p7m`, `.p7s`, `.tsd`, `.m7m`) in bulk. It
verifies CAdES signatures and time stamps against the European trusted lists (Italy, Romania,
France and every other country on the EU List of Trusted Lists). It writes an accessible HTML
report and, on request, extracts the signed documents safely. It is built for Windows, macOS
and Linux.

> Status: early development. Nothing is usable yet. We build the project step by step, test
> first. The [roadmap](docs/roadmap.md) shows what is done and what comes next.

## What does it do?

It checks every signed or time-stamped file in a folder and writes one report. Offices receive
and archive CAdES `.p7m`, detached `.p7s` and time-stamped `.tsd` and `.m7m` files, often
nested several layers deep. Opening them one by one is slow and tells little about the
signatures.

For each folder, SignSpector:

- finds every signed or time-stamped file in it and its subfolders (hidden folders and
  symbolic links met inside are skipped and listed in the report);
- opens every layer: BER/DER encoding (including indefinite lengths), base64 encoding, nested
  signatures, RFC 5544 time-stamped data;
- verifies each signature (RSA, RSA-PSS, ECDSA; SHA-1/2) and the signer's certificate
  (validity, key usage, qualified status);
- follows the chain up to a CA of the national trusted list of the certifier's country. It
  reaches that list through the
  [EU List of Trusted Lists](https://ec.europa.eu/tools/lotl/eu-lotl.xml) and chooses it
  automatically from the signatures found;
- checks whether the certificate was revoked, from data in the signature or the CA's
  revocation list (CRL): not one query per signature;
- verifies countersignatures and RFC 3161 time stamps;
- reports the results on the console and in a self-contained HTML report (and JSON for
  scripts);
- extracts the signed documents beside the originals, only on request:
  `Relazione.pdf.p7m` -> `Relazione.pdf`.

## Can it damage my documents?

No. Signed documents are often the only official copy, so SignSpector is built so that it
cannot damage them:

- `check` writes no document. It writes only the HTML report (in each folder, or at the
  `--report` path you name), the JSON file of `--json`, and its own cache of trusted lists and
  CRLs. Documents are written only by an extraction you ask for and confirm.
- After you choose a folder, it only counts: the signed or time-stamped files (the tool calls
  them "files to process") and the files of any kind. Then it asks before analysing.
- Writing documents needs a second confirmation on the complete write plan: you type the
  number of documents to write.
- A risky run gets a stronger warning that says why. You type the number of files to
  process. A run is risky when a chosen folder is a sensitive folder:
  - the root of a drive or volume;
  - the home folder, Desktop or Documents;
  - a system folder;
  - a network share root.

  A run is also risky when the folders chosen hold more than 10,000 files of any kind in all,
  subfolders included. A run that is not risky is an ordinary run. Files the analysis skips are
  not counted (hidden folders, symbolic links inside the folders, unreadable folders), and a file
  in overlapping folders counts once.
- From the context menu, the same confirmations appear in a window.
- In scripts, only these run:
  - `check` in an ordinary run, and `check --plan`;
  - `extract --plan` in an ordinary run;
  - the `--plan` lists of `undo`, the menu commands and `uninstall`.

  Everything else stops and says that a person must confirm.
- Originals are read-only. They are never modified, moved or renamed.
- Nothing is ever overwritten, not even an earlier report. Every file is created with an
  exclusive "create new" operation, so the operating system itself refuses to overwrite. A
  document, report or JSON file whose name is taken gets the next free name, for example
  `x (1).pdf`. A menu entry that is not SignSpector's is reported and left alone. The only files
  ever replaced are the tool's own cache and its list of what it installed; the full rule is R31
  in [docs/design.md](docs/design.md).
- Extracted documents are never written outside the chosen folder. File names taken from the
  signed files are made valid on Windows, macOS and Linux at once: no forbidden characters, no
  reserved names, no clashes that differ only in letter case or Unicode form.
- Every extracted document is recorded in the report with its SHA-256. An extraction never
  rewrites an earlier report: it writes a new one. `signspector undo` removes only the files
  that are still identical to what SignSpector wrote.
- `signspector uninstall` removes only what SignSpector installed, and never user data.

## Is it accessible?

Yes, by requirement. The target is EN 301 549, the standard referenced by the Italian
accessibility law (Legge 4/2004) and the AgID guidelines. The HTML report also targets WCAG 2.2
level AA:

- no information conveyed by colour or symbols alone;
- `NO_COLOR`, `--no-color` and a `--plain` mode for screen readers;
- no time limits on prompts;
- a semantic, keyboard-operable report that works without JavaScript.

## Which languages does it speak?

The operating system's language, or the one chosen with `--lang`. The report uses the same
language, or another one chosen with `--report-lang`. English and Italian come first. More
languages can be added without code changes.

## Which platforms will it run on?

Windows, macOS and Linux, with one self-contained executable per platform. It is written in
pure Rust: no OpenSSL, no runtime to install.

| Platform | Package |
|---|---|
| Windows x86_64 | `.exe` |
| macOS (Apple Silicon and Intel) | universal binary |
| Linux x86_64 | `.deb`, `.rpm`, static `.tar.gz` |

We plan context-menu entries for Explorer, Finder (Quick Actions), Nautilus and Dolphin. They
need no administrator rights.

## How will it be used?

```sh
signspector check   <folder>...   # analyse and write a report in each folder (default)
signspector extract <folder>...   # analyse, show the write plan, extract after confirmation
signspector undo    <report>      # remove the files a previous extraction wrote
signspector install-menu         # add the context-menu entries
signspector uninstall-menu       # remove only the context-menu entries
signspector uninstall            # remove everything SignSpector installed
```

Every command that changes something shows its plan first and acts only after you confirm.
The one exception is `check` in an ordinary run from a script, which writes its report and
the cache without a question.

- `extract` asks you to type the number of documents it will write.
- `undo`, `install-menu`, `uninstall-menu` and `uninstall` ask a yes/no question. The default
  is No.
- In scripts, these commands refuse. `--plan` shows the plan and stops.
- From the context menu, the same confirmations appear in a window, with the focus on Cancel.

There is no `--apply`, `--yes` or `--expect`.

## How do I build it?

Install [rustup](https://rustup.rs). The toolchain version is pinned in `rust-toolchain.toml`.

```sh
cargo build --release
cargo nextest run          # tests (cargo install cargo-nextest)
```

[docs/design.md](docs/design.md#how-do-i-build-it-on-the-mac) describes the cross builds for all
targets from macOS (mingw-w64, zig, cargo-zigbuild).

## How is it developed?

- Test first: every behaviour starts as a failing test.
- A second AI model reviews every step. It is not the model that wrote the code, so its review
  is not anchored on the author's reasoning.
- Every five commits, a coherence audit checks requirements, tests, code and documentation
  against each other. It verifies that every reference exists, and it surfaces unfinished work.
- This repository is public, so test data is synthetic only. Real signed documents contain
  personal data and never enter the repository: local git hooks (pre-commit, commit-msg,
  pre-push) refuse it. After cloning, run `git config core.hooksPath .githooks`.

Requirements and design are in [docs/design.md](docs/design.md), the order of work in
[docs/roadmap.md](docs/roadmap.md). Contributor rules are in [CLAUDE.md](CLAUDE.md), lessons on
the way of working in [docs/lessons.md](docs/lessons.md). Every text follows the writing guide,
[docs/writing.md](docs/writing.md).

## Which licence applies?

[MIT](LICENSE)

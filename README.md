# SignSpector

SignSpector checks signed and time-stamped files (`.p7m`, `.p7s`, `.tsd`, `.m7m`) in bulk. It
verifies CAdES signatures and time stamps against the European trusted lists (Italy, Romania,
France and every other EU/EEA country). It writes an accessible HTML report and, on request,
extracts the signed documents safely. It is built for Windows, macOS and Linux.

> Status: early development. Nothing is usable yet. We build the project step by step, test
> first. The [roadmap](docs/roadmap.md) shows what is done and what comes next.

## What does it do?

It checks every signed or time-stamped file in a folder and writes one report. Offices receive
and archive CAdES `.p7m`, detached `.p7s` and time-stamped `.tsd` and `.m7m` files, often
nested several layers deep. Opening them one by one is slow and tells little about the
signatures.

For each folder, SignSpector:

- finds every signed or time-stamped file in it and its subfolders (hidden folders and
  symbolic links are skipped and listed in the report);
- opens every layer: BER/DER envelopes (including indefinite lengths), base64 envelopes,
  nested signatures, RFC 5544 time-stamped data;
- verifies each signature (RSA, RSA-PSS, ECDSA; SHA-1/2) and the signer's certificate
  (validity, key usage, qualified status);
- follows the chain up to a CA of the national trusted list of the certifier's country. It
  reaches that list through the
  [EU List of Trusted Lists](https://ec.europa.eu/tools/lotl/eu-lotl.xml) and chooses it
  automatically from the signatures found;
- checks whether the certificate was revoked, from data in the signature or the CA's
  revocation list: not one query per signature;
- verifies countersignatures and RFC 3161 time stamps;
- reports the results on the console and in a self-contained HTML report (and JSON for
  scripts);
- extracts the signed documents beside the originals, only on request:
  `Relazione.pdf.p7m` → `Relazione.pdf`.

## Can it damage my documents?

No. Signed documents are often the only official copy, so SignSpector is built so that it
cannot damage them:

- Without an explicit `extract`, it writes no document. It writes only the report (in the
  folder, or at the `--report` or `--json` path you name) and its own cache of trusted lists
  and revocation lists.
- After you choose a folder, it only counts the envelopes (signed or time-stamped files) and
  asks before analysing them.
- Writing needs a second confirmation on the complete write plan: you type the number of
  documents to write.
- A risky folder gets a stronger warning, and you type the number of envelopes. Risky folders
  are:
  - the root of a drive or volume;
  - the home folder, Desktop and Documents;
  - system folders;
  - network share roots;
  - more than 10,000 envelopes in all the folders chosen.
- From the context menu, the same confirmations appear in a window.
- In scripts, only these run:
  - `check` on an ordinary folder, and `check --plan`;
  - `extract --plan` on an ordinary folder;
  - the `--plan` lists of `undo`, the menu commands and `uninstall`.

  Everything else stops and says that a person must confirm.
- Originals are read-only. They are never modified, moved or renamed.
- Nothing is ever overwritten. Every file is created with an exclusive "create new" operation,
  so the operating system itself refuses to overwrite. A name clash becomes `x (1).pdf`.
- Extracted documents are never written outside the chosen folder. File names taken from envelopes
  are made valid on Windows, macOS and Linux at once: no forbidden characters, no reserved names,
  no clashes that differ only in letter case or Unicode form.
- Every written file is logged with its SHA-256. `signspector undo` removes only the files that
  are still identical to what SignSpector wrote.
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

Every command that changes something shows its plan first and acts only after you confirm:

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

[docs/design.md](docs/design.md#building-on-the-mac) describes the cross builds for all
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
[docs/roadmap.md](docs/roadmap.md), contributor rules in [CLAUDE.md](CLAUDE.md). Every text
follows the writing guide, [docs/writing.md](docs/writing.md).

## License

[MIT](LICENSE)

# SignSpector

**Cross-platform batch verifier for CAdES signatures and time stamps** (`.p7m`, `.p7s`, `.tsd`,
`.m7m`) against the Italian AgID Trusted List, with an accessible HTML report and safe
extraction of the signed documents.

> **Status: early development.** Nothing is usable yet: the project is being built step by
> step, test first. See the [roadmap](docs/roadmap.md) for what is done and what comes next.

## What it does

Offices receive and archive documents that are digitally signed (CAdES `.p7m`, detached
`.p7s`) and time-stamped (`.tsd`, `.m7m`), often nested several layers deep. Opening them one by
one is slow and tells little about the signatures.

Point SignSpector at a folder and it will:

- **find** every signed or time-stamped file in it and its subfolders;
- **open** every layer: BER/DER envelopes (including indefinite lengths), base64 envelopes,
  nested signatures, RFC 5544 time-stamped data;
- **verify** each signature (RSA, RSA-PSS, ECDSA; SHA-1/2), the signer's certificate
  (validity, key usage, qualified status), the chain up to a CA of the
  [AgID Trusted List](https://eidas.agid.gov.it/TL/TSL-IT.xml), countersignatures and RFC 3161
  time stamps;
- **report** the results on the console and in a self-contained HTML report (and JSON for
  scripts);
- **extract**, only on request, the signed documents beside the originals:
  `Relazione.pdf.p7m` → `Relazione.pdf`.

## Safety by design

Signed documents are often the only official copy. SignSpector is built so that it cannot
damage them:

- **Dry run by default.** Without an explicit `extract`, nothing is written except the report.
- **Confirmation before anything happens.** After a folder is chosen, the tool only counts the
  files and asks before analysing. Writing needs a second confirmation on the complete write
  plan, by typing the number of files. Folders such as a drive root or the home folder, or
  more than 10,000 files, get a stronger warning. Scripts must state the expected count
  (`--yes --expect <n>`).
- **Originals are read-only.** They are never modified, moved or renamed.
- **Nothing is ever overwritten.** Every file is created with an exclusive "create new"
  operation, so the operating system itself refuses to overwrite. Name clashes become
  `x (1).pdf`.
- **Nothing is written outside the chosen folder.** File names taken from envelopes are made
  valid on Windows, macOS and Linux at once: no forbidden characters, no reserved names, no
  clashes that differ only in letter case or Unicode form.
- **Undo.** Every written file is logged with its SHA-256. `signspector undo` removes only
  files that are still identical to what SignSpector wrote.
- **Clean uninstall.** `signspector uninstall` removes only what SignSpector installed, and
  never user data.

## Accessibility

Accessibility is a requirement, not an afterthought. The targets are **EN 301 549**, the
standard referenced by the Italian accessibility law (Legge 4/2004) and the AgID guidelines,
and **WCAG 2.2 level AA** for the HTML report:

- no information conveyed by colour or symbols alone;
- `NO_COLOR`, `--no-color` and a `--plain` mode for screen readers;
- no time limits on prompts;
- a semantic, keyboard-operable report that works without JavaScript.

## Languages

The interface speaks the operating system's language, or the one chosen with `--lang`. The
report is written in the same language. English and Italian come first; more languages can be
added without code changes.

## Platforms

One self-contained executable per platform, written in pure Rust (no OpenSSL, no runtime to
install):

| Platform | Package |
|---|---|
| Windows x86_64 | `.exe` |
| macOS (Apple Silicon and Intel) | universal binary |
| Linux x86_64 | `.deb`, `.rpm`, static `.tar.gz` |

Context-menu integration is planned for Explorer, Finder (Quick Actions), Nautilus and Dolphin,
and needs no administrator rights.

## Planned usage

```sh
signspector check   <folder>      # analyse and write the report (default)
signspector extract <folder>      # analyse, show the write plan, extract after confirmation
signspector undo    <report>      # remove the files a previous extraction wrote
signspector install-menu --apply  # add the context-menu entries
signspector uninstall --apply     # remove everything SignSpector installed
```

Commands that change files or the system only show what they would do unless `--apply` is
given.

## Building from source

Requires [rustup](https://rustup.rs). The toolchain version is pinned in `rust-toolchain.toml`.

```sh
cargo build --release
cargo nextest run          # tests (cargo install cargo-nextest)
```

Cross builds for all targets from macOS (mingw-w64, zig, cargo-zigbuild) are described in
[docs/design.md](docs/design.md#building-on-the-mac).

## Development

- **Test-driven:** every behaviour starts as a failing test.
- **Independent review:** each step is reviewed by a second AI model, different from the one
  that wrote the code, so that the review is not anchored on the author's reasoning.
- **Coherence audits** every three commits: requirements, tests, code and documentation are
  checked against each other. Every reference is verified to exist, and unfinished work is
  surfaced.
- **Privacy:** this repository is public, so test data is synthetic only. Real signed documents
  contain personal data and never enter the repository; local git hooks (pre-commit,
  commit-msg, pre-push) refuse it. After cloning: `git config core.hooksPath .githooks`.

Requirements and design are in [docs/design.md](docs/design.md), the order of work in
[docs/roadmap.md](docs/roadmap.md), contributor rules in [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE)

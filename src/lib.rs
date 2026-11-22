//! SignSpector: finds signed and time-stamped files under a folder, verifies them and reports.

use std::path::Path;

/// Extensions of the envelopes SignSpector opens (CAdES, detached signatures, RFC 5544 time-stamped data).
pub const ENVELOPE_EXTENSIONS: [&str; 4] = ["p7m", "p7s", "tsd", "m7m"];

/// True when the file name ends with one of [`ENVELOPE_EXTENSIONS`], ignoring case.
#[must_use]
pub fn is_envelope(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| {
            ENVELOPE_EXTENSIONS
                .iter()
                .any(|e| e.eq_ignore_ascii_case(ext))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognises_every_envelope_extension() {
        for name in ["a.pdf.p7m", "a.p7s", "a.pdf.tsd", "a.m7m"] {
            assert!(is_envelope(Path::new(name)), "{name}");
        }
    }

    #[test]
    fn extension_case_is_ignored() {
        assert!(is_envelope(Path::new("Relazione.PDF.P7M")));
        assert!(is_envelope(Path::new("x.P7s")));
        assert!(is_envelope(Path::new("x.TSD")));
        assert!(is_envelope(Path::new("x.M7m")));
    }

    #[test]
    fn other_files_are_not_envelopes() {
        for name in [
            "a.pdf",
            "p7m",
            ".p7m",
            "a.p7m.pdf",
            "a.p7",
            "a.p7mx",
            "a.tsr",
            "a.p7m.",
            "a.p7m ",
            "a.p7m:Zone.Identifier",
            "",
        ] {
            assert!(!is_envelope(Path::new(name)), "{name}");
        }
    }

    #[test]
    fn directories_in_the_path_do_not_matter() {
        assert!(is_envelope(Path::new("archivio.p7m/sub/doc.pdf.p7m")));
        assert!(!is_envelope(Path::new("archivio.p7m/doc.pdf")));
    }

    #[cfg(windows)]
    #[test]
    fn windows_paths() {
        assert!(is_envelope(Path::new(r"C:\dir\a.P7M")));
    }

    /// Linux file names are bytes: a Latin-1 name must not be silently skipped.
    #[cfg(unix)]
    #[test]
    fn non_utf8_names() {
        use std::ffi::OsStr;
        use std::os::unix::ffi::OsStrExt;
        let path = |b: &[u8]| Path::new(OsStr::from_bytes(b)).to_path_buf();
        assert!(is_envelope(&path(b"rel\xE0zione.pdf.p7m")));
        assert!(!is_envelope(&path(b"a.p7m\xFF")));
        assert!(!is_envelope(&path(b"a.\xFFp7m")));
    }
}

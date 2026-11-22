//! SignSpector command line. All logic lives in the library (`src/lib.rs`) so it can be tested.

fn main() {
    println!(
        "SignSpector {} ({} {}): in development, not usable yet.",
        env!("CARGO_PKG_VERSION"),
        std::env::consts::OS,
        std::env::consts::ARCH
    );
}

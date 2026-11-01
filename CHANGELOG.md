# Changelog

All notable changes to hmectl are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - unreleased

First version.

### Added

- `new`, `list`, `deactivate`, `reactivate`, `login`, `logout` and `status`.
- Sign-in with SRP-6a and two-factor codes from a trusted device or by text message.
- The session is kept as one item in the login Keychain and used only after Touch ID or the login
  password.
- Requests are limited to Apple's hosts, and TLS must chain to a root built into macOS.
- `--json`, `--dry-run`, `--no-copy` and `--trace`; documented exit codes 0 to 4.
- zsh completion, installed with `sudo make install` into `/usr/local`.
- Commands that use the session wait for each other instead of running at the same time.

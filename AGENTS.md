# Instructions for coding agents

hmectl is a macOS Swift CLI that signs in to a person's Apple Account and manages their iCloud+ Hide My
Email aliases. It handles real credentials, so work conservatively.

## Commands

- `make test`: unit tests; they never reach the network.
- `make lint`: `swift format lint --strict` and `zsh -n` on the completion. `make format` fixes formatting.
- `make build`: release build, signed ad hoc with the hardened runtime.
- `python3 Scripts/generate-test-vectors.py`: regenerates `Tests/HMECoreTests/TestVectors.swift` after
  a change to the SRP or BigUInt code (standard library only).
- `HMECTL_LIVE_TESTS=1 make test ARGS="--filter LiveTLSTests"`: contacts Apple without credentials;
  run it only when asked.

## Boundaries

- Never run `hmectl login`, `new`, `deactivate`, `reactivate` or `logout` against a real account, and
  never read, print or copy the `hmectl` Keychain item.
- No third-party dependencies. Every request goes through `HTTPClient`, and new hosts need a
  `HostPolicy` change with a stated reason.
- Never print or log passwords, verification codes, tokens or cookies; `--trace` shows method, host
  and path only.
- Use synthetic accounts and addresses in tests and documentation.
- A new command or option updates `--help`, the README and `completions/_hmectl`.
- Keep comments to non-obvious intent. The version lives only in `Version.current`.

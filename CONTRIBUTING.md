# Contributing

Thanks for helping. hmectl is a small tool that handles Apple Account credentials, so please open an
issue before a large change. Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Set up and check

```sh
make test     # unit tests; they never reach the network
make lint     # swift format lint --strict, and zsh -n on the completion
make build    # release build
```

`HMECTL_LIVE_TESTS=1 swift test --filter LiveTLSTests` additionally checks the TLS policy against
Apple's hosts without credentials. Format with `make format`.

## Rules

- No third-party dependencies. The code uses only Apple's frameworks, so that it stays easy to audit.
- Every network request goes through `HTTPClient`, and a new host needs a change to `HostPolicy` with a
  reason in the pull request.
- A new command or option updates `--help`, the README and `completions/_hmectl`; tests check that they
  agree.
- Changes to the SRP or BigUInt code come with test vectors: extend `Scripts/generate-test-vectors.py`
  (standard library only) and regenerate `Tests/HMECoreTests/TestVectors.swift`.
- Use synthetic accounts and addresses in tests and examples, never real account data, codes or
  session values.
- Every bug fix comes with a test that fails without the fix.
- Keep comments to non-obvious intent.

## Pull requests

Fill in the pull request template. A change is merged when CI is green and the code owner (see
`.github/CODEOWNERS`) has reviewed it; changes to the sign-in, network, Keychain or SRP code get the
closest look. Commit messages are imperative and carry no AI attribution trailers.

## Versions and releases

Versions follow [Semantic Versioning](https://semver.org/). The version lives only in
`Sources/HMECore/Command.swift` (`Version.current`). User-visible changes get a line in
[CHANGELOG.md](CHANGELOG.md); a release is a tag `vX.Y.Z` on `main` with the matching changelog
section.

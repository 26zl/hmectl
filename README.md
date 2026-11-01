# hmectl

[![CI](https://github.com/26zl/hmectl/actions/workflows/ci.yml/badge.svg)](https://github.com/26zl/hmectl/actions/workflows/ci.yml)

Create and manage iCloud+ Hide My Email aliases from the macOS terminal.

```console
$ hmectl new netflix
quiet_fox_42@icloud.com
Created quiet_fox_42@icloud.com for "netflix" and copied it to the clipboard.
Mail sent to it is forwarded to you@example.com.
```

hmectl is unofficial and not affiliated with Apple. It uses the same private web API as icloud.com,
which Apple can change or block at any time, and this use may not be covered by Apple's terms.

## Requirements

- macOS 13 or later
- Swift 6.2 or later (Xcode 26, or the Command Line Tools: `xcode-select --install`)
- iCloud+ and an Apple Account with two-factor authentication and a trusted phone number

## Install

```sh
git clone https://github.com/26zl/hmectl.git
cd hmectl
make test
make build          # release build, signed ad hoc with the hardened runtime
sudo make install   # copies it to /usr/local/bin, plus the zsh completion
hmectl login
```

Without sudo: `make install PREFIX="$HOME/.local"`, then add `~/.local/bin` to your `PATH` (and
`~/.local/share/zsh/site-functions` to `fpath` for completion). A binary in your home folder can be
replaced by any program running as you.

To uninstall, run `hmectl logout`, then `sudo make uninstall` (with the same `PREFIX` if you set one).

## Usage

| Command | What it does |
| --- | --- |
| `hmectl new <label> [--note <text>]` | Creates an alias, prints it and copies it to the clipboard. |
| `hmectl list [--active \| --inactive]` | Lists your aliases, newest first. |
| `hmectl deactivate <alias \| id>` | Stops forwarding mail sent to the alias. |
| `hmectl reactivate <alias \| id>` | Forwards mail sent to the alias again. |
| `hmectl login [--apple-id <account>]` | Signs in with your password and a verification code. |
| `hmectl logout` | Signs out at Apple and deletes the saved session. |
| `hmectl status` | Shows which account is signed in, without contacting Apple. |

Options: `--json` (`new`, `list`, `status`), `--dry-run` (`new`, `deactivate`, `reactivate`: show what
would change without changing it), `--no-copy` (`new`), `--trace` (each request's method, host and
path, on stderr), `--help` and `--version`. Data goes to stdout and messages to stderr.

Exit status: `0` success, `1` error, `2` usage error, `3` not signed in or session expired,
`4` cancelled. `logout` exits with `1` if Apple did not confirm the sign-out.

hmectl does not delete aliases; do that in Settings (Apple Account > iCloud > Hide My Email).

## Security

- Your password is used for SRP-6a sign-in and is never sent or saved.
- The session is one item named `hmectl` in your login Keychain. Other programs that read it get a
  Keychain prompt; deny prompts you did not expect.
- `new`, `list`, `deactivate`, `reactivate` and `logout` ask for Touch ID or your login password first.
- Requests go only to `idmsa.apple.com`, `setup.icloud.com` and your account's `*.icloud.com` Hide My
  Email host, over HTTPS without following redirects, and the certificate must chain to a root built
  into macOS.
- The session reaches as much as icloud.com does (Mail, iCloud Drive and more); `hmectl logout` ends it.
- hmectl cannot protect against other programs running as you.

Report vulnerabilities as described in [SECURITY.md](SECURITY.md), not in a public issue.

## Limits

- One alias per command, and Apple limits how many you can create.
- With Advanced Data Protection, *Access iCloud Data on the Web* must be on.
- Apple's newer sign-in prompt on your devices is not supported. If no code appears on a device, press
  Return at the code prompt to get one by text message.
- Security keys and accounts on icloud.com.cn are not supported.
- Interactive only: signing in needs a terminal, and every use needs Touch ID or your password.

## Development

```sh
make test   # unit tests, no network
make lint
HMECTL_LIVE_TESTS=1 make test ARGS="--filter LiveTLSTests"   # TLS checks against Apple, no credentials
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). The protocol details follow [pyicloud](https://github.com/timlaing/pyicloud) and
[pysrp](https://github.com/cocagne/pysrp). Apple, iCloud and Hide My Email are trademarks of Apple Inc.

# hmectl

[![CI](https://github.com/26zl/hmectl/actions/workflows/ci.yml/badge.svg)](https://github.com/26zl/hmectl/actions/workflows/ci.yml)

Create and manage iCloud+ **Hide My Email** aliases from the macOS terminal.

```console
$ hmectl new netflix
quiet_fox_42@icloud.com
Created quiet_fox_42@icloud.com for "netflix" and copied it to the clipboard.
```

hmectl is for people who want a fresh alias without opening Settings or a browser, and who want to
know exactly what the tool does with their Apple Account. It is small (about 2,000 lines of Swift),
has no third-party dependencies, and talks only to Apple.

hmectl is not made by or affiliated with Apple. Apple offers no public API for Hide My Email, so
hmectl uses the same private web API as icloud.com. Read [Limits](#limits) before you rely on it.

**Status:** early (0.1.x). It works against Apple's web API as it is today, and that API can change
without notice.

## Requirements

- macOS 13 or later on a Mac with Touch ID or a login password (any Mac).
- Swift 6.2 or later: Xcode 26 or later, or its Command Line Tools (`xcode-select --install`).
- An iCloud+ subscription and an Apple Account with two-factor authentication through a trusted device
  or a text message. Accounts that use security keys are not supported.

## Install

```sh
git clone https://github.com/26zl/hmectl.git
cd hmectl
make test
make build                   # release build, signed ad hoc with the hardened runtime
sudo make install            # copies it to /usr/local/bin, plus zsh completion
hmectl login
```

`sudo make install` only copies files, so nothing is compiled as root. The installed binary is owned
by root, so a program running as you cannot replace it, and `/usr/local/bin` is on the default macOS
`PATH`. To install without sudo, use `make install PREFIX=~/.local` and put `~/.local/bin` on your
`PATH`; a binary in your home folder can be swapped by anything running as you, so deny Keychain
prompts you did not expect. No prebuilt binaries are published: the code you read is the code you run.

To uninstall, sign out first so the session ends at Apple and leaves your Keychain:

```sh
hmectl logout
sudo make uninstall          # or: make uninstall PREFIX=~/.local
```

## Usage

| Command | What it does |
| --- | --- |
| `hmectl new <label> [--note <text>]` | Creates an alias with that label, prints it and copies it to the clipboard. |
| `hmectl list [--active \| --inactive]` | Lists your aliases, newest first. |
| `hmectl deactivate <alias \| id>` | Stops forwarding mail sent to the alias. |
| `hmectl reactivate <alias \| id>` | Forwards mail sent to the alias again. |
| `hmectl login [--apple-id <account>]` | Signs in with your password and a verification code. |
| `hmectl logout` | Signs out at Apple and deletes the saved session. |
| `hmectl status` | Shows which account is signed in, without contacting Apple. |

Options: `--json` (machine-readable output for `new`, `list` and `status`), `--dry-run` (for `new`,
`deactivate` and `reactivate`: show what would change and change nothing; `new --dry-run` does not
contact Apple, the others read your alias list), `--no-copy` (for `new`), `--trace` (print every
request's method, host and path to stderr), `--help` and `--version`. Data goes to stdout and messages
to stderr, so `alias=$(hmectl new shop)` works in scripts.

Exit status: `0` success, `1` error, `2` usage error, `3` not signed in or session expired,
`4` cancelled.

Deleting an alias is left to Settings (Apple Account > iCloud > Hide My Email), where it can be done
deliberately. A deactivated alias can be reactivated; a deleted one is gone.

## How it works

- **Sign in** (`hmectl login`): the password is used for SRP-6a (RFC 5054, 2048-bit group, SHA-256)
  with Apple's PBKDF2 password processing, so the password itself is never sent, not even to Apple.
  Apple then asks for a code from one of your devices or by text message, and iCloud starts a web
  session the way icloud.com does.
- **`new`, `list`, `deactivate`, `reactivate`**: Touch ID (or your login password), then the saved
  session from the Keychain, a check with iCloud, and the Hide My Email call (`generate` + `reserve`
  for `new`).

## Security model

- **No password storage.** hmectl never saves your password, and asks for it again only when Apple
  ends the session.
- **One Keychain item.** The session (session token, trust token, iCloud cookies, account id and the
  Hide My Email host) is a single generic password named `hmectl` in your login Keychain. The Keychain
  lets the binary that saved it read it silently and shows a prompt to every other program. After you
  rebuild or upgrade, the first run asks once; a prompt you did not expect means something else wants
  the session, so deny it.
- **Touch ID before use.** `new`, `list`, `deactivate` and `reactivate` ask for Touch ID, an Apple
  Watch or your login password before they use the session. `login` asks for your Apple Account
  password first and only then reads the earlier session, to reuse Apple's trust in this client;
  `logout` uses it only to end it at Apple; `status` reads only the account name.
- **Only Apple hosts.** Requests can go only to `idmsa.apple.com`, `setup.icloud.com` and the
  `*.icloud.com` Hide My Email host iCloud assigns to your account, over HTTPS on port 443. Redirects
  are never followed. This is enforced in code (`HostPolicy.swift`), not just documented.
- **Only built-in roots.** A TLS certificate must pass the system's checks and chain to a root
  certificate built into macOS, so a root added by a user, a configuration profile or a TLS-inspecting
  proxy is refused.
- **Hardened runtime.** The installed binary refuses injected libraries and debugger attachment, and
  the default install location is owned by root.
- **One command at a time.** Commands that use the session take a lock, so two runs never overwrite
  each other's session.
- **What you cannot narrow.** The saved session is an iCloud web session with the same reach as
  icloud.com (Mail, Contacts, iCloud Drive and more). hmectl uses only Hide My Email, but someone who
  steals the session could use more. `hmectl logout` ends it at Apple; so does *Sign Out of All
  Browsers* at icloud.com.

Check it yourself: run any command with `--trace`, watch the connections with a firewall such as
[LuLu](https://objective-see.org/products/lulu.html), and read the code. The SRP code is tested against RFC 5054 appendix B and against vectors from
an independent Python implementation of the client pyicloud uses
([`Scripts/generate-test-vectors.py`](Scripts/generate-test-vectors.py)).

## Limits

- **Unofficial.** hmectl relies on Apple's private web API and identifies itself as the iCloud web
  client. Apple can change or block it at any time, and this use may not be covered by Apple's terms.
  Use it at your own risk.
- **One alias per command.** There is no bulk mode. Apple also limits how many aliases you can create;
  others have observed about five per 30 minutes.
- **Advanced Data Protection** turns off *Access iCloud Data on the Web*, and iCloud then refuses Hide
  My Email requests from hmectl. Turning web access back on is a trade-off only you can make.
- **Two-factor authentication**: hmectl accepts a code from a device when one is shown, and otherwise
  a code by text message. Apple's newer device prompt for browsers is not implemented, and neither are
  security keys.
- **Interactive by design**: signing in needs a terminal, and using the session needs Touch ID or your
  password, so hmectl cannot run unattended.
- Only accounts on icloud.com; accounts in mainland China (icloud.com.cn) are not supported.

## Development

```sh
make test                                              # unit tests, no network
HMECTL_LIVE_TESTS=1 swift test --filter LiveTLSTests   # TLS policy against Apple, no credentials
make lint                                              # swift format lint --strict, zsh -n on the completion
python3 Scripts/generate-test-vectors.py               # regenerate the test vectors (standard library only)
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Getting help

Open an issue for a bug or an idea; the templates ask for what helps. Report security problems
privately as described in [SECURITY.md](SECURITY.md), never in a public issue, and never share your
password, verification codes or anything from the `hmectl` Keychain item.

## Acknowledgements

The sign-in and Hide My Email protocol details follow [pyicloud](https://github.com/timlaing/pyicloud)
and [pysrp](https://github.com/cocagne/pysrp) (both MIT), and
[RFC 5054](https://www.rfc-editor.org/rfc/rfc5054) for SRP.

## License

[MIT](LICENSE)

Apple, iCloud, iCloud+, Hide My Email, Touch ID and Keychain are trademarks of Apple Inc., registered in
the U.S. and other countries. hmectl is an independent project and is not affiliated with, endorsed by or
sponsored by Apple.

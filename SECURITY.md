# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and
choose **Report a vulnerability** (private vulnerability reporting). Do not open a public issue for a
security problem. You can expect an acknowledgement within a week.

Useful details: the hmectl version (`hmectl --version`), your macOS version, the command, and the
`--trace` output if it helps. `--trace` shows only methods, hosts, paths and status codes. Never send
your Apple Account password, verification codes, the Keychain item or any other part of a session.

## Supported versions

Only the latest release, and `main`, receive security fixes.

## Scope

hmectl signs in to the user's Apple Account and keeps an iCloud web session in the login Keychain. Of
particular interest are ways to:

- make it contact a host other than Apple's sign-in, iCloud setup and Hide My Email hosts, or accept a
  certificate that does not chain to a root built into macOS;
- read or use the saved session without the Keychain prompt or the Touch ID check;
- leak the password, verification codes or session tokens into output, logs or files;
- make text from Apple's responses control the terminal.

Weaknesses in Apple's own services belong with Apple: <https://security.apple.com>.

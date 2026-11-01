---
name: Bug report
about: Report a problem with hmectl
title: ''
labels: bug
assignees: ''
---

**What happened**
A clear description of the problem. For a security problem, follow
[SECURITY.md](https://github.com/26zl/hmectl/blob/main/SECURITY.md) instead of filing here.

**To reproduce**
The exact command you ran, for example `hmectl list --trace`.

**Expected behavior**
What you expected to happen.

**Output**
Paste the relevant output. `--trace` shows only methods, hosts, paths and status
codes. Never paste your password, verification codes, aliases you want to keep
private, the address they forward to (`forwardTo` in `--json` output), or anything
from the `hmectl` Keychain item.

**Environment**
- hmectl version (`hmectl --version`):
- macOS version:
- Swift version (`swift --version`):

**Additional context**
Anything else that helps.

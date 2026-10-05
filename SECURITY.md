# Security policy

## Reporting a vulnerability

Please do not report a security problem in a public issue. Report it in private instead: on this
repository's **Security** tab, choose
[**Report a vulnerability**](https://github.com/gzurl/agent-squad/security/advisories/new). Only
the maintainer sees the report.

Tell us what you found, how to reproduce it, which release you ran (the last line of
`.agent-squad/install.log`), and what an attacker could do with it.

## Supported versions

Only the latest release is supported: a fix ships in a new release, and projects take it with
`/squad-upgrade`.

## Scope

Anything this repository ships or runs on a machine:
- the one-line installer, `install.sh`;
- the release's installer and scripts;
- the pre-push gate and the merge gate;
- the session hooks;
- the commands;
- the squad board mod.

A rule of the charter that lets an agent do something unsafe counts too.

## What happens next

The maintainer reads each report and answers you on it. A confirmed problem is fixed through the
squad's usual review, and the advisory is published with the release that fixes it, crediting you
unless you prefer otherwise.

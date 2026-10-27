# Security

## Reporting a vulnerability

Please report security problems privately, through the repository's
[private reporting form](https://github.com/jbinder/sprawlrun/security/advisories/new),
not in a public issue. Only the maintainer sees the report. Say what an
attacker could do, and how to reproduce it if you can.

This is a one-person project maintained in spare time. Reports are answered as
soon as possible, and a confirmed problem is fixed in a release before it is
discussed in public.

## Supported versions

Only the latest release gets fixes — from
[F-Droid](https://f-droid.org/packages/io.github.jbinder.sprawlrun) or the
[GitHub releases](https://github.com/jbinder/sprawlrun/releases/latest).

## What is in scope

The app has no `INTERNET` permission, no accounts and no server, so what it can
be attacked through is what it reads from outside itself:

- **Mission packs** imported from a file
- **Backup files** imported from a file, and the automatic-backup folder
- **Notifications**, including what a tap on one hands back to the app
- **Permissions** it holds: location, physical activity, notifications, and the
  one folder chosen for automatic backups

A run log is private data — routes show where someone lives and runs. Anything
that lets another app or file read it, or makes the app write it somewhere the
runner did not choose, is in scope too.

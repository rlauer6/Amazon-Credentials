# Release Notes — Amazon::Credentials 1.3.2

**Release Date:** 2026-08-08
**Distribution:** `Amazon-Credentials-1.3.2`
**Author:** Rob Lauer &lt;rclauer@gmail.com&gt;

---

## Overview

This is a patch release focused on improving the reliability and
debuggability of web identity (OIDC/JWT) credential retrieval via
`get_creds_from_web_identity`. It also includes internal build system
improvements from `CPAN::Maker::Bootstrapper`.

---

## What's New

### Bug Fixes

#### `get_creds_from_web_identity` — Correct Default Region Fallback

- Fixed a subtle but meaningful operator precedence issue in the default region resolution chain. The expression:
  ```perl
  $self->get_region // $ENV{AWS_DEFAULT_REGION} // $ENV{AWS_REGION} // DEFAULT_REGION;
  ```
  has been corrected to:
  ```perl
  $self->get_region // $ENV{AWS_DEFAULT_REGION} // $ENV{AWS_REGION} || DEFAULT_REGION;
  ```

The final `||` (instead of `//`) ensures the constant `DEFAULT_REGION`
is used as a fallback when the environment variable resolves to an
empty string, not just when it is `undef`.

#### `get_creds_from_web_identity` — Improved STS Error Reporting

- The error message emitted on a failed `AssumeRoleWithWebIdentity`
  STS call now uses `$rsp->code` (the HTTP status code integer)
  instead of `$rsp->status_line` (which does not exist).

### New Features

#### `_decode_jwt_claims` — JWT Payload Introspection (Debug Only)

- Added a new private method `_decode_jwt_claims($token)` that decodes
  the claims payload from a JWT/OIDC token (base64url => base64 =>
  JSON). This is used exclusively in debug mode to log token claims
  for troubleshooting web identity credential failures.
- The method is safe to call with malformed or empty tokens and will
  return a descriptive error hash rather than dying.
- **No new CPAN dependencies are required.** The method uses
  `MIME::Base64` (core) and `JSON::PP` (already a dependency).

#### `get_creds_from_web_identity` — Additional Debug Logging

- When `debug` is enabled, the following additional information is now
  logged during a web identity credential exchange:
  - Token length and an obfuscated token excerpt (reversed, uppercased prefix)
  - Decoded JWT claims payload (via `_decode_jwt_claims`)
- The STS host URL continues to be logged with the token omitted for security.

---

## Build System Changes

The following build infrastructure files were updated by
`CPAN::Maker::Bootstrapper`. These changes have no effect on the
installed module or its behaviour.

- `.gitignore` — Added `extra-files.mk`
- `.includes/git.mk` — Added `repo` target for creating GitHub
  repositories via `gha-aws`
- `.includes/help.mk` — Refactored help output to write to a temp file
  and page through `$PAGER` (falls back to `less`, `more`, or `cat`);
  updated variable documentation
- `.includes/release-notes.mk` — Added `--dryrun` support via `DRYRUN`
  environment variable; fixed `##` comment placement for `make help`
- `.includes/update.mk` — Added `bash-completion.mk` and `modulino.mk`
  to `MANAGED_FILES`; reordered `update` steps so `post-update` runs
  before `Makefile` is replaced
- `.includes/version.mk` — `release`, `minor`, and `major` targets now
  depend on `clean` to prevent stale build artifacts from carrying
  forward across version bumps
- `Makefile` — Various improvements:
  - Added `GITHUB_ACTIONS` tool detection (`gha-aws`)
  - Added `SOURCE_FILES_IN` variable; `deps.mk` and dependency scan
    targets now depend on `.pm.in` source files rather than built
    `.pm` files
  - `modulino` and bash-completion targets moved to included `.mk` files
  - Added `extra-files.mk` generation target and `-include` for it
  - `all` target is now `.PHONY` and builds the tarball directly
  - `update-available` is now an order-only prerequisite of the tarball target
- `builder` — Fixed a logic inversion: the branch checkout inside the
  CI builder script now correctly checks for the presence of `.git`
  before attempting `git checkout`

---

## Upgrade Notes

This release is a drop-in replacement for `1.3.1`. No API changes, no
new required dependencies, and no changes to credential search
behaviour.

---

## Links

- [GitHub Repository](https://github.com/rlauer6/perl-Amazon-Credentials)
- [MetaCPAN](https://metacpan.org/pod/Amazon::Credentials)
- [CI Build Status](https://github.com/rlauer6/Amazon-Credentials/actions/workflows/build.yml)

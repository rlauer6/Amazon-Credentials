# Release Notes: Amazon-Credentials 1.3.1

**Date:** 2026-08-01
**Author:** Rob Lauer \<rclauer@gmail.com\>
**Distribution:** [Amazon-Credentials](https://metacpan.org/pod/Amazon::Credentials)

---

## Overview

Version 1.3.1 is a maintenance release focused on a correctness fix
for the `cache => 0` (no-cache) mode introduced in 1.3.0, along with a
significant overhaul of the build system infrastructure via
`CPAN::Maker::Bootstrapper`.

---

## Bug Fixes

### Credential Getter Behaviour with `cache => 0`

The `new` constructor previously called `reset_credentials()`
immediately after setting credentials when caching was disabled. This
wiped out the closures right after population, before any getter had a
chance to return a value, effectively making credentials unreachable
on the first call.

This immediate reset has been removed. Credentials are now cleared
lazily — on a per-getter basis — only after the value has been
returned to the caller.

A new internal method, `_get_credential`, centralises this logic for
all three credential getters:

- `get_aws_access_key_id`
- `get_aws_secret_access_key`
- `get_token`

**Previous behaviour (broken):**
```perl
# With cache => 0, credentials were wiped immediately in new()
# before any caller could read them.
my $creds = Amazon::Credentials->new( cache => 0 );
$creds->get_aws_access_key_id;   # returned undef
```

**New behaviour (correct):**
```perl
# Credentials are available on first call; the closure is wiped
# immediately after the value is returned.
my $creds = Amazon::Credentials->new( cache => 0 );
$creds->get_aws_access_key_id;   # returns the key; closure is then cleared
```

When `cache => 0` and the closure has already been spent (subsequent
calls), `_get_credential` re-fetches credentials via
`find_credentials` before returning the value and clearing again.

> **Note:** `credential_keys()` remains the recommended way to
> retrieve the full credential tuple atomically when caching is
> disabled.

---

## Build System Changes

This release incorporates a substantial update to the
`CPAN::Maker::Bootstrapper`-managed build infrastructure. These
changes do not affect the runtime behaviour of `Amazon::Credentials`.

### `perl.mk`

- Replaced `podextract` detection with `podchecker`
  (`Pod::Checker`). POD validation is now run as part of the `%.pm`
  and `%.pl` build rules via `podchecker`, failing the build if POD
  errors are found.
- Introduced `PERLCRITIC_SEVERITY` (default: `5`) and
  `PERLCRITIC_THEME` (default: `pbp`) variables.
- `tidy_on` and `critic_on` are now conditionally defined only when
  `perltidy` / `perlcritic` are present on `PATH`.
- Syntax checking (`SYNTAX_CHECKING`) is no longer suppressed when
  `LINT=off`.
- Compile-skip list can now be supplied via a `compile.skip` file in
  addition to the `PERLWC_SKIP` make variable.
- For `.pl` scripts, the erroneous `-M"$$module"` flag has been
  removed from the `perl -wc` syntax check.
- Added a `check-syntax` phony target as a convenience alias for
  building all modules and scripts (with syntax checking bundled into
  the build rules).
- `deps.mk` is now included unconditionally; its self-remake rule
  depends on `.pm.in`/`.pl.in` source files rather than the built
  `.pm`/`.pl` targets, eliminating the chicken-and-egg problem during
  `make clean`.
- `project.mk` is now included unconditionally.

### `Makefile`

- Default goal changed from `all` to `$(TARBALL)`.
- `cpanfile` is now generated from three separate intermediate files (`cpanfile.requires`, `cpanfile.recommends`, `cpanfile.suggests`) using `cpan-maker create-cpanfile`.
- New targets: `recommends`, `suggests`, `recommends.raw`, `suggests.raw`.
- Dependency scanning now uses `scandeps-static` (replaces `scandeps-static.pl`) and produces separate raw files per dependency tier via a grouped target (`requires.raw recommends.raw suggests.raw &:`).
- The inline `scan-deps` and `filter_requires` shell/Perl macros have been replaced by `cmb filter`.
- `deps.mk` is regenerated from source `.pm.in` files via `cmb create-deps`.
- Added a `package` target (`clean` + `LINT=on SCAN=on`).
- `make-cpan-dist.pl` references replaced with `cpan-maker`.
- `md-utils.pl` reference replaced with `markdown-render`.
- `README.md` generation now degrades gracefully with a warning when `Markdown::Render` or `Pod::Markdown` are not installed.
- Git configuration commands now suppress errors with `2>/dev/null`.
- `buildspec.yml` is now created with mode `0644`.
- `CMB_UPDATE_CHECK` and `CMB_VERSION_DRIFT` variables introduced (defaults: `on` and `fail`).
- `config.mk` is now included at the top of the Makefile.

### `update.mk`

- `update-available` now supports two independent checks:
  - **CPAN version check** (controlled by `CMB_UPDATE_CHECK=on|off`): compares the installed bootstrapper version against the published CPAN version.
  - **Local drift check** (controlled by `CMB_VERSION_DRIFT=fail|warn|ignore`): verifies local managed files match the installed bootstrapper via `md5sum`.
- `post-update` now merges new entries from the bootstrapper's `gitignore` into the project's `.gitignore`.
- Shell syntax in `update` and `post-update` corrected (missing semicolons and backslashes in multi-line shell blocks).

### `release-notes.mk`

- The release notes target has been simplified to delegate entirely to `cmb release-notes`.

### `git.mk`

- `git init` output suppressed (`>/dev/null`).
- `NO_COMMIT=1` environment variable support added to skip the final commit.
- Fixed shell syntax in the commit block (proper semicolons and continuation).

### `builder`

- Default installer flags updated to include `--no-prebuilt --show-build-log-on-failure --verbose`.
- Extra dependencies updated: `CPAN::Maker::Bootstrapper` added; version pins on `CPAN::Maker` and `Markdown::Render` removed.
- Local volume mount added to `docker run` in `build-ci` for working-directory access.
- `git clone` is skipped if the target directory already exists.
- `git checkout` is skipped if `.git` already exists in the working directory (supports mounted local builds).
- `CMB_VERSION_DRIFT=ignore` passed to `make` to suppress drift errors in CI.
- `NO_ECHO=` passed to `make` for full build output in CI.

### `cpanfile`

- Entries sorted alphabetically.
- `suggests "the", ""` added.

### `.gitignore`

- Extended with additional patterns for generated build artefacts: `*.raw`, `*.tmp`, `*.checked`, `*.crit`, `*.tdy`, `*.pl`, `*.pm`, `*.sh`, `*.gz`, `*.log`, editor backup files, and template files.

### New Files

- `deps.mk` — auto-generated inter-module dependency graph.
- `project.mk` — project-local make rules and `clean-local` hook.
- `recommends` — soft (non-eval) optional dependency declarations.
- `suggests` — eval-wrapped optional dependency declarations.

---

## Upgrade Notes

- No changes to the public API.
- The `cache => 0` fix is transparent; no caller changes are required.
- Build tooling now requires `CPAN::Maker::Bootstrapper` and the `cmb` command-line tool. Install with:
  ```
  cpanm CPAN::Maker::Bootstrapper
  ```

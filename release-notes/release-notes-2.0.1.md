# Amazon::Credentials 2.0.1 Release Notes

**Release Date:** September 23, 2026
**Distribution:** Amazon-Credentials-2.0.1

---

## Overview

Version 2.0.1 is a security-focused patch release that addresses
potential credential exfiltration via object dumps in
`Amazon::Credentials::Provider`. Sensitive credential values are now
stored as closures rather than plain object attributes, preventing
them from appearing in serialized output such as `Data::Dumper` dumps
or log output.

---

## What's New

### Security Enhancement: Closure-Based Credential Storage

The primary change in this release is a hardening of
`Amazon::Credentials::Provider` to prevent credential leakage through
object introspection or serialization.

#### Changes to `Amazon::Credentials::Provider`

- **Removed** `aws_access_key_id`, `aws_secret_access_key`, and
  `token` from the `mk_accessors` list. These attributes are no longer
  stored as plain hash values on the object.
- **Added** explicit getter/setter pairs that store credential values
  inside Perl closures, keeping them hidden from object dump
  utilities:
  - `get_aws_access_key_id` / `set_aws_access_key_id`
  - `get_aws_secret_access_key` / `set_aws_secret_access_key`
  - `get_token` / `set_token`
- **Updated** the `new` constructor to:
  - Extract credential arguments from the options hash before passing
    to the parent constructor (`delete` rather than pass-through),
    ensuring raw credential values are never stored as object
    attributes.
  - Use the new setter methods to initialise credential values as
    closures.

#### Security Benefit

Storing credentials via closures means that tools such as
`Data::Dumper`, `YAML`, or logging frameworks that inspect object
internals will not expose plaintext credential values. This is
consistent with the closure-based approach introduced in
`Amazon::Credentials` itself in the 1.3.0 release.

---

### New Test

- **`t/27-provider-security.t`** — New test suite validating that
  credential values stored in `Amazon::Credentials::Provider`
  instances are not exfiltrated through object dumps or direct hash
  access.

---

## Dependency Updates

The following minimum version requirements have been bumped:

| Module | Previous | New |
|---|---|---|
| `Date::Format` | 2.24 | 2.35 |
| `JSON` | 4.10 | 4.11 |
| `Role::Tiny::With` | 2.002004 | 2.002005 |

The `Test::Without::Module` test dependency has been removed.

---

## Build System Updates

This release includes several improvements to the
`CPAN::Maker::Bootstrapper`-managed build infrastructure:

- **`.includes/bootstrap.mk`** — Added to the managed includes set.
- **`.includes/perl.mk`** — Improved build output clarity:
  - Syntax and POD checks now emit labelled `Checking SYNTAX...`,
    `Checking POD...`, and `Checking TIDINESS...` / `Checking
    PERLCRITIC...` progress messages with `OK` confirmation on
    success.
  - `perlcritic` output is now suppressed from stdout on success
    (redirected to `/dev/null`).
- **`.includes/update.mk`** — `bootstrap.mk` added to the list of
  managed files.
- **`Makefile`**:
  - `find-files` macro now supports an optional fourth filename
    pattern argument, enabling test helper modules (`*.pm`, `*.pl`)
    under `t/` to be included in `TESTS`.
  - `test-requires.raw` scan now filters out modules provided by the
    distribution itself (via a `provides` target), avoiding false
    self-dependencies in test requirements.
  - `PERL5LIB` is now explicitly set when invoking `scandeps-static`
    and `cpan-maker` to ensure locally installed dependencies under
    `local/lib/perl5` are found.
  - `extra-files` and `extra-files.mk` generation refactored to use
    `cmb extra-files`; `extra-files.mk` is excluded during bootstrap
    builds.
  - A stray trailing semicolon in the `gen-vars-file` call has been corrected.

---

## Upgrade Notes

The getter/setter interface for credential values on
`Amazon::Credentials::Provider` instances is unchanged from the
caller's perspective — `get_aws_access_key_id`,
`get_aws_secret_access_key`, and `get_token` continue to work as
before. However, **direct hash access** to
`$provider->{aws_access_key_id}`,
`$provider->{aws_secret_access_key}`, or `$provider->{token}` will no
longer return credential values. Any code relying on direct hash
access to these keys must be updated to use the accessor methods.

---

## Previous Release

See [release notes for 2.0.0](release-notes/release-notes-2.0.0.md)
for details of the major provider-based architecture introduced in the
prior release.

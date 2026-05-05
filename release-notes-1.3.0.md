# Amazon::Credentials 1.3.0 Release Notes

## Overview

This release migrates the build system from autoconf/automake to
`CPAN::Maker::Bootstrapper`, reduces the module's static dependency
footprint through lazy loading, and replaces the encryption-based
credential storage with a closure-based approach that is both simpler
and more effective. The credential search order and public API are
unchanged.

---

## Security

**Encryption replaced by closure-based credential storage**

The passkey/`Crypt::CBC` encryption approach introduced in 1.1.0 has
been completely removed and replaced with Perl closures.

The encryption approach added meaningful complexity - two XS
dependencies, a passkey management strategy, and an encrypt/decrypt
round-trip on every credential access - without addressing the
fundamental exposure risk. Even with an externally sourced passkey,
the plaintext credential is returned in the clear by every getter call
and remains vulnerable to the same log and serialization exposure the
encryption was meant to prevent. The closure approach eliminates the
exposure at the source rather than obscuring it in transit.

Credentials are no longer stored as plain scalar attributes on the
object. Each credential value is captured in a closure and retrieved
by calling a code reference - making the values invisible to
`Data::Dumper`, JSON serializers, exception stack traces, and any
other object introspection:

```perl
use Data::Dumper;
print Dumper Amazon::Credentials->new;
# _access_key_id     => sub { "DUMMY" },
# _secret_access_key => sub { "DUMMY" },
# _session_token     => sub { "DUMMY" },
```

The closure approach has no runtime cost, no XS dependencies, and no
passkey to manage.

The `passkey`, `no_passkey_warning`, `encryption`, `cipher`,
`encrypt`, `decrypt`, `insecure`, and `create_passkey` options and
methods are removed. `Crypt::CBC` and `Crypt::Cipher::AES` are
removed from `requires` and `test-requires`.

**`t/06-security.t` and `t/07-encryption.t` removed**

These tests covered the encryption machinery which no longer exists.
The closure approach makes credential exposure via object
introspection structurally impossible rather than merely tested.

---

## Build System

**Autoconf/automake completely removed**

`configure.ac`, `bootstrap`, all `Makefile.am` files, the entire
`autotools/` macro directory, the RPM spec, and the old AWS CodeBuild
`buildspec.yml` are gone. The project is now governed by a
`CPAN::Maker::Bootstrapper`-managed `Makefile` with `.includes/` for
managed targets (`perl.mk`, `git.mk`, `help.mk`, `release-notes.mk`,
`update.mk`, `upgrade.mk`, `version.mk`).

**Project layout normalized**

Source files moved from the autotools tree to standard locations:

| Was | Now |
|---|---|
| `src/main/perl/lib/` | `lib/` |
| `src/main/bash/bin/` | `bin/` |
| `src/main/perl/t/` | `t/` |
| `src/main/perl/UnitTestSetup.pm` | `UnitTestSetup.pm` |
| `cpan/recommends` | `recommends` |

**GitHub Actions CI**

`.github/workflows/build.yml` and `builder` are added, bringing the
full Bootstrapper CI pipeline: `make workflow`, `make build-ci`, and
`make update-available`. See the `CPAN::Maker::Bootstrapper`
documentation for details.

**`README-BUILD.md` and `README-TESTING.md` added**

`README-BUILD.md` documents build dependencies and how to build from
source. `README-TESTING.md` documents the test suite, which tests
require live AWS credentials, and how to run them.

---

## `amazon-credentials.sh`

This script has been replaced by the modulino wrapper
`amazon-credentials`.

## Module Changes

**Lazy loading of heavyweight dependencies**

Several modules needed only on infrequently-exercised code paths are
now loaded on demand rather than at compile time, reducing cold-start
overhead:

- `Config::Tiny` - loaded only when reading `~/.aws/credentials`
- `File::HomeDir` - loaded only when constructing the config path
- `POSIX::strptime` and `Time::Local` - loaded only in `_iso8601_to_time`
- `Getopt::Long` - loaded only in `main` (the modulino entry point)

**`JSON` → `JSON::PP`**

`use JSON` replaced with `use JSON::PP`. `JSON::PP` is a core module
since Perl 5.14 and eliminates the XS dependency for the common HTTP
response parsing path. `JSON` remains pinned with `+` in `requires`
as an optional accelerator.

**`Date::Format` removed from static imports**

Used only for debug log timestamps. The timestamp is now produced
with `scalar localtime`. `Date::Format` remains in `test-requires`
for tests that exercise time formatting.

**`Amazon::Credentials::HTTP::Response` simplified**

No longer inherits from `Class::Accessor::Fast`. It is now a minimal
bless-and-delegate wrapper around the `HTTP::Tiny` response hash.
The public interface (`content`, `content_type`, `is_success`,
`code`, `message`) is unchanged.

---

## Test Changes

**`t/12-error.t`** - Fixed a latent test dependency on `$EVAL_ERROR`
being cleared as a side effect of the old `decrypt` method's internal
`eval`. The fix uses `local $EVAL_ERROR` to correctly scope the
assertion.

**`t/14-utils.t`** - new test for `populate_creds()` method

**`t/02-web-identity.t`** - `no_passkey_warning => 1` removed from
constructor calls now that the passkey feature no longer exists.

**`t/04-process.t`** - Creates its own executable so we no longer need
to package a script for the test.

**`t/00-amazon-credentials.t`** - New smoke test confirming the
module loads cleanly.

---

## Deleted

`t/06-security.t`, `t/07-encryption.t`, `check-expired-token.pl`,
`test-aws-credentials.pl`, `TBD`, `target-repo`,
`perl-Amazon-Credentials.spec.in`, `release-notes.mk`,
`cpan/buildspec.yml`, `cpan/extra-files`, `cpan/requires`,
`cpan/test-requires`, and the complete `autotools/` directory.

---

## Dependencies

**Added:** `HTTP::Tiny 0.088`, `JSON::PP 4.16`

**Removed:** `Crypt::CBC`, `Crypt::Cipher::AES`, `MIME::Base64` (unused)

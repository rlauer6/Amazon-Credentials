# Amazon::Credentials 1.4.0 Release Notes

**Released:** Thu Sep 7 2026  
**Author:** Rob Lauer \<rclauer@gmail.com\>

---

## Overview

Version 1.4.0 adds first-class support for **AWS IAM Identity Center
(SSO) profiles** in the credential search chain, including automatic
token refresh when a cached SSO access token has expired.  This
release also hardens debug logging against credential leakage,
improves the HTTP layer, adds security guidance for CLI credential
loading, and fixes several bugs.

---

## New Features

### SSO Profile Support in Credential Files

`Amazon::Credentials` can now resolve credentials directly from AWS
config profiles that use IAM Identity Center (SSO), both the modern
`[sso-session NAME]` form and the legacy inline `sso_*` form.

When a profile contains `sso_account_id` and `sso_role_name`, the module:

1. Locates the correct SSO token cache file (using
   `sha1(session-name)` or `sha1(sso_start_url)`, matching AWS CLI
   behaviour).
2. Selects the freshest valid token when multiple cache files are
   present.
3. Automatically attempts to refresh an expired token if the cache
   contains a valid `refreshToken` and client registration — no manual
   `aws sso login` required unless the refresh also fails.
4. Normalises the SSO expiration (returned as epoch milliseconds) to
   the ISO-8601 UTC form used by all other credential sources.

New constructor options to support SSO profiles resolved via
`find_credentials`:

| Option | Description |
|---|---|
| `sso_role_name` | IAM Identity Center role name |
| `sso_account_id` | AWS account ID for the SSO role |
| `sso_region` | SSO region (falls back to `region`) |

### Automatic SSO Token Refresh (`_refresh_sso_access_token`)

When the best candidate token in the SSO cache has expired, the module
now attempts a token refresh against the AWS OIDC endpoint
(`oidc.<region>.amazonaws.com/token`) using the stored `clientId`,
`clientSecret`, and `refreshToken`. On success the refreshed token is
written back to the cache file atomically (via a temporary file and
rename), preserving original file permissions.

### Improved SSO Cache Scanning (`_get_access_token`)

The previous implementation used `File::Find`, which changed the
working directory as a side-effect. This has been replaced with a
simple `opendir`/`readdir` loop. When multiple token files are present
the module now picks the one with the latest `expiresAt` rather than
the first file encountered.

### Credential-Safe Debug Logging

`Amazon::Credentials` now sanitizes potentially sensitive values before
writing them to debug logs. The previous `safe_dumper` implementation,
which applied regular-expression substitutions to serialized output, has
been replaced by a recursive `_sanitize` helper.

The sanitizer:

Redacts AWS access keys, secret keys, session tokens, SSO/OIDC tokens,
authorization headers, and other known credential fields.
Recursively sanitizes hashes and arrays.
Clones `HTTP::Request` objects and redacts sensitive headers without
modifying the request that will actually be sent.
Sanitizes JSON credential responses before logging them.
Redacts opaque response bodies when their contents cannot be safely
inspected.
Preserves non-sensitive diagnostic information where possible.

Request and response logging for IMDS, ECS/container credentials, web
identity, SSO, credential-process output, and credential files now uses
the common sanitization path.

The built-in debug logger also now evaluates lazy logging callbacks,
matching the behavior expected when using Log4perl and avoiding the cost
of constructing debug output when debugging is disabled.

Tests in `t/10-logging.t` cover recursive sanitization, HTTP request
headers, HTTP credential responses, opaque response bodies, and
non-mutation of the original data.

### New Helper Functions

| Function | Purpose |
|---|---|
| `get_creds_from_sso` | Fetches role credentials from a parsed SSO profile section |
| `_sso_cache_key` | Computes `sha1_hex` of a session name or start URL |
| `_refresh_sso_access_token` | Calls the OIDC token endpoint to refresh an expired access token |
| `_write_sso_cache_file` | Atomically writes a refreshed token back to the SSO cache |
| `_iso8601_utc` | Formats an epoch timestamp as `YYYY-MM-DDTHH:MM:SSZ` |
| `_parse_expires_at` | Parses the several `expiresAt` date formats produced by different AWS CLI versions |
| `_sanitize` | Recursive credential scrubber |

### `export_credentials` Now Accepts Multiple Credential Shapes

`export_credentials` previously only understood `AWS_*`
environment-variable keys. It now also accepts the camelCase
`roleCredentials` shape returned by `GetRoleCredentials`
(`accessKeyId` / `secretAccessKey` / `sessionToken`), so callers no
longer need to remap keys before calling it.

### `status_line` Added to `Amazon::Credentials::HTTP::Response`

The response wrapper now exposes a `status_line` method (returning
`"<code> <reason>"`), consistent with `LWP::UserAgent` responses and
used internally for diagnostic logging.

### Security Guidance: CLI Credential Loading

A new section in the documentation covers best practices
for using the `amazon-credentials` modulino to load credentials into a
shell:

```bash
eval "$(amazon-credentials --role AWSAdministratorAccess --account 000000000)"
```

Key points documented:

- Prefer `eval "$(...)"` over copy-pasting output to avoid credentials
  appearing in shell history.
- Check for success before relying on exported variables.
- Do not run under `set -x` (shell trace mode).
- `--role` and `--account` arguments are not sensitive; only the
  emitted values are.

---

## Bug Fixes

- **`get_role_credentials`**: Region is now resolved _before_ calling
  `_get_access_token`, so the correct regional OIDC/SSO endpoint is
  used when no access token is passed by the caller.
- **`UserAgent::request`**: HTTP header field names carrying a leading
  `:` sigil (used internally by `HTTP::Headers` to suppress `_`→`-`
  translation) are now stripped before being handed to
  `HTTP::Tiny`. This fixes a rejection of the `x-amz-sso_bearer_token`
  header that would cause SSO `GetRoleCredentials` calls to fail.
- **`set_sso_credentials` POD**: Corrected "set AWS credential
  environment variables" (was "set", now "sets").
- **`builder`**: Fixed a regression where `CPAN::Maker::Bootstrapper`
  was being overwritten (`>`) rather than appended (`>>`) to the
  `build-requires` file.
- **Credential file profile handling**: `credential_process` is now read
  only from the selected profile rather than from an unrelated top-level
  configuration value.

- **Region resolution**: Region lookup now consistently honors the selected
  profile across `~/.aws/config` and `~/.aws/credentials`, including profiles
  that obtain credentials via `credential_process` or SSO.

- **Web identity STS endpoint**: `AssumeRoleWithWebIdentity` now uses the
  resolved regional STS endpoint consistently, including
  `sts.us-east-1.amazonaws.com` for `us-east-1`, rather than treating
  `us-east-1` as a request for the legacy global STS endpoint.

- **EC2 instance credentials**: IMDS role credential retrieval has been
  simplified to deterministic role-discovery and credential-fetch requests,
  avoiding malformed retry URLs and repeated role-name appends after
  unexpected metadata responses.

- **Container credential refresh**: `refresh_credentials` now refreshes
  credentials obtained through `AWS_CONTAINER_CREDENTIALS_FULL_URI` as well
  as classic ECS relative-URI credentials.

- **Credential normalization**: `populate_creds` no longer modifies the
  provider data structure passed to it while normalizing credential names.

- **JSON implementation selection**: The module now uses `JSON`, allowing
  `JSON::XS` to be used when available while retaining `JSON::PP` as the
  fallback implementation.
  
---

## Internal / Build Changes

- `Cwd` (`getcwd`) dependency removed from `Amazon::Credentials`; no
  longer needed after the `File::Find` → `opendir` refactor.
- `Time::Local` (`timegm_modern`) added as an explicit dependency,
  used by `_parse_expires_at`.
- `Digest::SHA` loaded lazily (via `require`) in `_sso_cache_key`.
- `Makefile`: `PACKAGE_VERSION` exported to the environment;
  `extra-files` target added to ensure `extra-files.mk` can always be
  generated cleanly; `gen-vars-file` call ordering fixed for
  `$(MODULE_PATH).in`.
- `test-requires.skip`: Added `Amazon::Credentials` and
  `Amazon::Credentials::HTTP::UserAgent` to prevent the dependency
  scanner from treating internal modules as external test
  requirements.
- New test file `t/15-sso-refresh.t` covering the token-refresh path.
- `JSON::PP` is no longer used directly; `JSON` selects `JSON::XS` when
  available and falls back to `JSON::PP`.

---

## Upgrade Notes

- No breaking API changes. Existing callers are unaffected.
- If you use the `amazon-credentials` CLI with `--role`/`--account`
  and your cached SSO token has expired, the tool will now attempt an
  automatic refresh rather than failing immediately. If no refresh
  token is available, `aws sso login` is still required.
- The `File::Find` module is no longer used by this distribution.

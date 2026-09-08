# Amazon::Credentials 2.0.0

**Released:** 2026-09-08  
**Author:** Rob Lauer <rclauer@gmail.com>

---

## Overview

Version 2.0.0 is a major release featuring a complete architectural
rework of credential discovery. The monolithic `find_credentials`
approach has been replaced with a modular, provider-based system. The
public `Amazon::Credentials` facade retains backward compatibility
where possible, but internal APIs have changed substantially.

---

## Breaking Changes

### Architecture: Provider-Based Credential Discovery

Credential discovery has been completely rearchitected. Each
credential source is now implemented as a discrete provider class. The
`Amazon::Credentials` object acts as a public facade that selects,
sequences, and delegates to providers.

**Removed methods and functions:**

- `find_credentials()` — replaced by the internal provider resolution
  pipeline
- `populate_creds()` — internal utility, no longer part of the public
  API
- `get_creds_from_env()`, `get_creds_from_role()`,
  `get_creds_from_container()`, `get_creds_from_web_identity()`,
  `get_creds_from_process()`, `get_creds_from_ini_file()`,
  `get_creds_from_sso()` — all replaced by dedicated provider classes
- `get_default_region()` / `get_ec2_credentials()` — removed
- `refresh_credentials()` — use `refresh_token()` directly
- `get_region_from_config()`, `get_region_from_env()` — internal, removed
- `set_credentials($options)` — signature changed; now only accepts a
  credential hash, not a trigger for discovery
- `reset_credentials($renew)` — `$renew` parameter removed; method now
  only clears credentials
- `_sanitize()` — renamed to `sanitize()` and made a public method
- `session_token_required`, `container`, `role`, `imdsv2_token`
  accessors — removed from the facade

**Changed behavior:**

- `reset_credentials()` no longer re-discovers credentials when called
  with a true value.
- The `source` attribute now reflects the credential source reported
  by the selected provider, not a file path.
- `credential_keys()` no longer includes
  `AWS_SESSION_TOKEN_EXPIRATION`.
- `imdsv2` now accepts string values (`preferred`, `required`,
  `disabled`) in addition to `0`/`1` booleans. The default changes
  from `true` (IMDSv2 required) to `preferred` (attempt IMDSv2, fall
  back to IMDSv1).

### Profile Selection Restricts Discovery

When a profile is explicitly selected (via the `profile` option or
`AWS_PROFILE` environment variable) and neither `order` nor `plugins`
is supplied, discovery is now restricted to the file/profile resolver
only. This prevents environment, container, or instance-role
credentials from taking precedence over an explicitly requested
profile.

### `order` Validation

Invalid provider names in `order` now raise `unknown credentials
plugin '...'` rather than `invalid credential location in search
order`.

### SSO Constructor Options

`sso_role_name` and `sso_account_id` now construct a `Provider::SSO`
object directly rather than setting `%ENV` and re-running discovery
via `env` order.

---

## New Features

### Provider Classes

The following new provider and role classes implement credential discovery:

| Class | Source |
|---|---|
| `Amazon::Credentials::Provider` | Base class for all providers |
| `Amazon::Credentials::Provider::Env` | AWS environment variables |
| `Amazon::Credentials::Provider::Container` | ECS container credential endpoint |
| `Amazon::Credentials::Provider::InstanceRole` | EC2 instance metadata service |
| `Amazon::Credentials::Provider::WebIdentity` | OIDC/JWT via STS `AssumeRoleWithWebIdentity` |
| `Amazon::Credentials::Provider::Process` | `credential_process` helper |
| `Amazon::Credentials::Provider::Config` | Static credentials from config/credentials files |
| `Amazon::Credentials::Provider::SSO` | AWS IAM Identity Center / SSO |
| `Amazon::Credentials::Provider::AssumeRole` | `role_arn` with `source_profile` or `credential_source` |
| `Amazon::Credentials::Resolver::Profile` | Resolves AWS profiles to the appropriate provider |
| `Amazon::Credentials::Role::File` | Role for reading AWS configuration files |
| `Amazon::Credentials::Role::SSOCache` | Role for managing the SSO token cache |
| `Amazon::Credentials::Utils` | Shared utilities |

### Custom Provider Registration

Third-party credential providers can now be registered and included in
the discovery chain:

```perl
Amazon::Credentials->register_provider('My::Credentials::Provider::CredentialBroker');

my $credentials = Amazon::Credentials->new(
    order => [qw(credential_broker env file)],
);
```

Registration must precede use. `order` and `plugins` control
participation and precedence; registration controls availability.

### `plugins` Constructor Option

A new `plugins` option restricts the set of providers that may
participate in discovery:

```perl
my $credentials = Amazon::Credentials->new(
    plugins => [qw(env file)],
);
```

When both `plugins` and `order` are supplied, `plugins` defines
availability and `order` defines precedence. A provider selected by
`order` but absent from `plugins` raises an exception.

Constraining the provider set can also avoid unnecessary discovery
latency in environments where particular credential sources are known
not to apply.

### Expanded Profile Resolution Support

The profile resolver (`Amazon::Credentials::Resolver::Profile`) now
supports the major AWS profile credential mechanisms used by this
distribution:

- Static access keys
- `credential_process`
- AWS IAM Identity Center / SSO (both modern `sso_session` and legacy inline profiles)
- Web identity (`role_arn` + `web_identity_token_file`)
- `AssumeRole` with `source_profile` (recursive, cycle-detected)
- `AssumeRole` with `credential_source` (`Environment`, `Ec2InstanceMetadata`, `EcsContainer`)
- `AssumeRole` with `mfa_serial`

This resolves the limitation documented in previous releases where
profile-based `role_arn` / `source_profile` chaining was not
supported.

### MFA Support

MFA-assisted `AssumeRole` profiles using `mfa_serial` are now
supported. Supply the current token via the
`AMAZON_CREDENTIALS_MFA_TOKEN` environment variable:

```shell
AMAZON_CREDENTIALS_MFA_TOKEN=123456 \
  AWS_PROFILE=admin \
  amazon-credentials
```

The `amazon-credentials` CLI also gains a `--token` / `-t` option for
specifying the MFA token directly.

```
amazon-credentials \
  --profile amazon-credentials-mfa-test \
  --token 123456
```

### `get_provider`

A new `get_provider` accessor returns the provider object that
actually produced the credentials. For profile-based credentials this
is the resolved provider (e.g. `Provider::AssumeRole`), not the
profile resolver itself. This is important because credential refresh
is delegated to the producing provider.

### `get_expiration` / `set_expiration`

Expiration is now stored on the provider object. `get_expiration`
delegates to the selected provider. `set_expiration` sets expiration
on the provider and is retained primarily for compatibility.

### `sanitize()` (formerly `_sanitize()`)

The credential sanitization helper is now a public method named
`sanitize()`. It recursively redacts credential-shaped values from
data structures, `HTTP::Request` objects, and
`Amazon::Credentials::HTTP::Response` objects prior to diagnostic
logging.

### IMDSv2 `preferred` Mode

The `imdsv2` option now defaults to `preferred`. In this mode
`Amazon::Credentials` attempts IMDSv2 token acquisition first and,
if token acquisition fails, falls back to IMDSv1 rather than treating
the token failure as fatal.

---

## Dependency Changes

### New runtime dependencies

- `Amazon::Signature4::Lite` >= 1.0.5
- `Role::Tiny`
- `Role::Tiny::With` >= 2.002004
- `URI::Escape` >= 5.36

### New test dependencies

- `Class::Accessor::Fast` >= 0.51
- `Role::Tiny::With` >= 2.002004

---

## Test Suite Changes

- `t/15-sso-refresh.t` — **deleted**; SSO token refresh is now tested
  through the provider-level tests.
- New provider-level test files added: `t/16-provider-env.t` through
  `t/26-resolver-profile.t`.
- `t/01-credentials.t` — `source` is now `config` rather than the file
  path.
- `t/02-credentials.t` — rewritten to cover provider objects,
  `set_provider`, `set_expiration`, `refresh_token`, and the legacy
  SSO constructor path.
- `t/02-web-identity.t` — integration tests for
  `get_creds_from_web_identity` moved to
  `t/22-provider-web-identity.t`.
- `t/03-container.t` — `find_credentials()` return-value test removed.
- `t/10-logging.t` — updated to pass explicit credentials and to use
  `sanitize()` instead of `_sanitize()`.
- `t/11-order.t` — extended with subtests covering `plugins`,
  profile-driven resolver selection, and plugin/order interaction
  rules.
- `t/12-error.t` — extended with STDERR capture for error output.
- `t/13-env.t` — region is no longer read from `~/.aws/config` when
  using the `env` provider; test updated accordingly.
- `t/14-utils.t` — `populate_creds()` tests removed (function no
  longer exists).

---

## Compatibility Notes

The public facade (`Amazon::Credentials`) retains the following
interfaces from earlier releases:

- Explicit credential construction (`aws_access_key_id`, `aws_secret_access_key`, `token`)
- `credential_keys()`, `as_string()`, `format_credentials()`
- `get_aws_access_key_id()`, `get_aws_secret_access_key()`, `get_token()`, `get_aws_session_token()`
- `is_token_expired()`, `refresh_token()`
- `set_credentials()`, `reset_credentials()`
- `normalize_arn()`, `get_role_credentials()`, `set_sso_credentials()`
- `sso_role_name` / `sso_account_id` constructor options
- `order` constructor option
- `raise_error` / `print_error` / `get_error`

Internal provider implementations, resolver classes, and
underscore-prefixed methods are not considered stable public
interfaces.

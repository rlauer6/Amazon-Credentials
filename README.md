# Table of Contents

* [NAME](#name)
* [SYNOPSIS](#synopsis)
* [DESCRIPTION](#description)
  * [Amazon::API Integration](#amazonapi-integration)
  * [Botocore Alignment](#botocore-alignment)
  * [MFA Support](#mfa-support)
* [ADDING CREDENTIAL PROVIDERS](#adding-credential-providers)
  * [Provider Contract](#provider-contract)
  * [Provider Registration and Selection](#provider-registration-and-selection)
  * [Providers Versus Resolvers](#providers-versus-resolvers)
* [CREDENTIAL PROVIDERS](#credential-providers)
  * [Profile Resolution](#profile-resolution)
* [CONSTRUCTOR](#constructor)
  * [new](#new)
  * [Constructor Options](#constructor-options)
    * [aws\_access\_key\_id / aws\_secret\_access\_key](#aws\access\key\id--aws\secret\access\key)
    * [cache](#cache)
    * [debug](#debug)
    * [imdsv2](#imdsv2)
    * [logger](#logger)
    * [order](#order)
    * [plugins](#plugins)
    * [profile](#profile)
    * [print\_error](#print\error)
    * [raise\_error](#raise\error)
    * [region](#region)
    * [sso\_account\_id / sso\_role\_name](#sso\account\id--sso\role\name)
    * [sso\_region](#sso\region)
    * [timeout](#timeout)
    * [token](#token)
    * [user\_agent](#user\agent)
* [CREDENTIAL ACCESS](#credential-access)
  * [get\_aws\_access\_key\_id](#get\aws\access\key\id)
  * [get\_aws\_secret\_access\_key](#get\aws\secret\access\key)
  * [get\_token](#get\token)
  * [get\_aws\_session\_token](#get\aws\session\token)
  * [credential\_keys](#credential\keys)
  * [as\_string](#as\string)
  * [format\_credentials](#format\credentials)
* [PROVIDER INFORMATION](#provider-information)
  * [get\_provider](#get\provider)
  * [get\_source](#get\source)
  * [get\_region](#get\region)
* [TEMPORARY CREDENTIALS AND REFRESH](#temporary-credentials-and-refresh)
  * [get\_expiration](#get\expiration)
  * [set\_expiration](#set\expiration)
  * [is\_token\_expired](#is\token\expired)
  * [refresh\_token](#refresh\token)
* [EXPLICIT CREDENTIAL MANAGEMENT](#explicit-credential-management)
  * [set\_credentials](#set\credentials)
  * [reset\_credentials](#reset\credentials)
* [AWS PROFILE FEATURES](#aws-profile-features)
  * [Static Credentials](#static-credentials)
  * [credential\_process](#credential\process)
  * [AssumeRole](#assumerole)
  * [Web Identity](#web-identity)
  * [AWS IAM Identity Center / SSO](#aws-iam-identity-center--sso)
* [EXPORTED FUNCTIONS](#exported-functions)
  * [normalize\_arn](#normalize\arn)
  * [get\_role\_credentials](#get\role\credentials)
  * [set\_sso\_credentials](#set\sso\credentials)
* [ERROR HANDLING](#error-handling)
* [SECURITY CONSIDERATIONS](#security-considerations)
  * [Credential Storage](#credential-storage)
  * [Caching](#caching)
  * [Sanitizing Diagnostic Data](#sanitizing-diagnostic-data)
  * [Logging](#logging)
  * [IAM Permissions](#iam-permissions)
* [COMMAND LINE INTERFACE](#command-line-interface)
* [COMPATIBILITY](#compatibility)
* [INCOMPATIBILITIES](#incompatibilities)
* [CONTRIBUTING](#contributing)
* [LICENSE AND COPYRIGHT](#license-and-copyright)
* [AUTHOR](#author)
# NAME

Amazon::Credentials - discover and manage AWS credentials

# SYNOPSIS

    use Amazon::Credentials;

    my $credentials = Amazon::Credentials->new;

    my $access_key_id     = $credentials->get_aws_access_key_id;
    my $secret_access_key = $credentials->get_aws_secret_access_key;
    my $session_token     = $credentials->get_token;

    Use a named AWS profile:

    my $credentials = Amazon::Credentials->new( profile => 'sandbox' );

Or select the credential providers to search:

    my $credentials = Amazon::Credentials->new( order => [qw(env file container role)] );

Supply credentials explicitly:

    my $credentials = Amazon::Credentials->new(
      aws_access_key_id     => $access_key_id,
      aws_secret_access_key => $secret_access_key,
      token                 => $session_token,
    );

Retrieve credentials using standard AWS environment variable names:

    my $keys = $credentials->credential_keys;

    {
      AWS_ACCESS_KEY_ID     => ...,
      AWS_SECRET_ACCESS_KEY => ...,
      AWS_SESSION_TOKEN     => ...,
    }

# DESCRIPTION

`Amazon::Credentials` discovers AWS credentials and presents them through
a single interface.

The module uses a provider-based credential model. Credential sources are
implemented by provider classes, while `Amazon::Credentials` acts as the
public facade that:

- selects which credential providers may participate in discovery;
- controls the order in which top-level providers are searched;
- resolves AWS profiles into the provider that actually supplies credentials;
- retains the selected provider so temporary credentials can be refreshed;
- provides compatibility methods for applications written against earlier
versions of `Amazon::Credentials`.

## Amazon::API Integration

`Amazon::API` uses `Amazon::Credentials` for AWS credential discovery
and management.

With the provider-based architecture introduced in version 2.0.0,
`Amazon::API` can rely on `Amazon::Credentials` for substantially more
than static access keys or basic environment and profile lookup. Profile
resolution may now include assumed roles, recursive `source_profile`
chains, `credential_source`, `credential_process`, web identity,
AWS IAM Identity Center / SSO, MFA-assisted AssumeRole, ECS container
credentials, and EC2 instance role credentials.

This keeps credential discovery and refresh policy in
`Amazon::Credentials`, while `Amazon::API` can concentrate on AWS API
request construction, signing, and service behavior.

`Amazon::Credentials` remains a standalone distribution and does not
require `Amazon::API`.

## Botocore Alignment

The credential model is intentionally aligned with the major credential
mechanisms and profile semantics supported by Botocore. The goal is not
strict behavioral parity, but to support the credential sources and
composition rules commonly used by AWS applications.

In particular, `Amazon::Credentials` supports:

- environment credentials;
- shared credentials and configuration files;
- `credential_process`;
- web identity credentials;
- AWS IAM Identity Center / SSO;
- ECS container credentials;
- EC2 instance role credentials;
- `AssumeRole` using `source_profile`;
- recursive role chains;
- `credential_source` using `Environment`, `Ec2InstanceMetadata`, or `EcsContainer`.

There are deliberate differences from Botocore.

- Credential precedence and ordering

    `Amazon::Credentials` does not attempt to reproduce Botocore's exact
    provider ordering. Provider precedence is configurable through `order`
    and `plugins`.

    Configurable provider selection can also avoid unnecessary discovery
    latency by skipping credential sources that are known not to apply in
    a given environment.

- Legacy Boto2 configuration files are not supported.
- Other differences

    The module also does not attempt to duplicate Botocore's internal
    provider classes, exception hierarchy, retry behavior, or other
    implementation details where they are not required to resolve
    credentials correctly.

The intended compatibility boundary is AWS credential configuration and
resolution semantics, not Botocore's internal architecture.

## MFA Support

MFA-assisted `AssumeRole` profiles using `mfa_serial` are supported.

When a selected profile contains `mfa_serial`,
`Amazon::Credentials` requires the current MFA token in the
`AMAZON_CREDENTIALS_MFA_TOKEN` environment variable.

The variable is an `Amazon::Credentials` convention and is not defined
by AWS.

For example:

    AMAZON_CREDENTIALS_MFA_TOKEN=123456 \
      AWS_PROFILE=admin \
      amazon-credentials

The token is passed to STS as `TokenCode`, while `mfa_serial` is passed
as `SerialNumber`.

MFA tokens are not retained by the provider. If temporary credentials
are refreshed, a current `AMAZON_CREDENTIALS_MFA_TOKEN` value must be
available at refresh time.

The same convention can be used when running any application that
discovers credentials through `Amazon::Credentials`.

For example:

    AMAZON_CREDENTIALS_MFA_TOKEN=123456 \
      AWS_PROFILE=my-profile \
      some-script

In this form, both environment variables are scoped to that process
invocation. The script selects `my-profile`, the resolver reads
`mfa_serial` from that profile, and the supplied MFA token is used for
the resulting `AssumeRole` request.

This is generally preferable to exporting
`AMAZON_CREDENTIALS_MFA_TOKEN` into the shell environment because the
token is needed only for the credential acquisition operation and has a
short validity period.

# ADDING CREDENTIAL PROVIDERS

`Amazon::Credentials` supports registration of additional top-level
credential providers.

This facility is intended primarily for environments that obtain AWS
credentials from infrastructure outside the standard AWS credential
chain. Examples might include an organization-provided credential broker,
a local credential agent, or a platform-specific metadata service that
already issues AWS credentials.

It should generally not be necessary to create a custom provider merely
to alter how standard AWS profiles are interpreted. Profile composition,
including `credential_process`, SSO, web identity, `source_profile`,
`credential_source`, and assumed roles, belongs in the profile resolver.

Similarly, a provider should not normally introduce a new mechanism for
persisting long-lived AWS credentials. Applications should prefer
short-lived credentials issued by an authenticated credential service
over custom credential files or embedded secrets.

## Provider Contract

A provider is registered with:

    Amazon::Credentials->register_provider('My::Credentials::Provider');

The provider name is derived from the final component of the package
name and converted to snake\_case.

For example:

    My::Credentials::Provider::CredentialBroker
        => credential_broker

A top-level provider constructor receives the current discovery context
as a hash reference.

A provider may return `undef` when it is not applicable in the current
environment.

If it returns an object, that object must represent usable credentials
and provide the interface expected by `Amazon::Credentials::Provider`.

Custom providers will normally subclass `Amazon::Credentials::Provider`
so that the common credential accessors and default refresh behavior are
inherited.

The `credentials` method returns the normalized credential tuple used by
the facade.

`is_refreshable` reports whether the provider can refresh its credentials.
A refreshable provider implements `refresh_credentials` and owns its
refresh mechanism. Refreshing credentials must not require
`Amazon::Credentials` to rediscover the provider.

## Provider Registration and Selection

A custom provider must be registered before it can be used.

    Amazon::Credentials->register_provider('My::Credentials::Provider::CredentialBroker');

Registration makes the provider known to
`Amazon::Credentials`. It does not automatically
add the provider to the default credential chain.

After registration, the provider may be selected through `order` or
`plugins`.

    Amazon::Credentials->register_provider('My::Credentials::Provider::CredentialBroker');

    my $credentials = Amazon::Credentials->new( order => [qw(credential_broker env file)], );

Installing or loading a provider module is not sufficient. Until the
provider is registered, `Amazon::Credentials` does not know that it is
available.

This separation is intentional. Registration controls availability;
`order` and `plugins` control participation and precedence.

## Providers Versus Resolvers

A provider produces credentials.

A resolver interprets configuration and selects the provider that should
produce those credentials.

This distinction is important.

For example, an AWS profile containing:

    role_arn = ...
    source_profile = ...

does not itself produce credentials. The profile resolver interprets the
configuration, resolves the source profile, and constructs an
`AssumeRole` provider.

Custom extensions should preserve the same separation. If an extension
primarily interprets configuration or delegates to other providers, it
is probably a resolver rather than a credential provider.

# CREDENTIAL PROVIDERS

The built-in top-level credential providers are:

- `env`

    Credentials supplied through AWS environment variables.

- `container`

    Credentials supplied through the ECS container credential endpoint.

- `role`

    Credentials supplied through the EC2 instance metadata service.

- `web_identity`

    Credentials obtained using a web identity token and
    `AssumeRoleWithWebIdentity`.

- `file`

    AWS configuration and credentials files.

    The `file` entry is a profile resolver. A profile may resolve to static
    credentials or to another credential-producing provider.

The default search order is:

    env
    container
    role
    web_identity
    file

This is the default policy of `Amazon::Credentials`. It is configurable
and is not intended to duplicate Botocore's provider order exactly.

## Profile Resolution

AWS profiles are resolved according to the contents of
`~/.aws/credentials` and `~/.aws/config`.

A profile may resolve to:

- static access keys;
- `credential_process`;
- AWS IAM Identity Center / SSO credentials;
- web identity credentials;
- an assumed role using `role_arn` and `source_profile`;
- an assumed role using `role_arn` and `credential_source`.

`source_profile` resolution is recursive. A source profile may itself
resolve through another supported credential mechanism.

Recursive role chains are supported and cycles are rejected.

Supported `credential_source` values are:

    Environment
    Ec2InstanceMetadata
    EcsContainer

# CONSTRUCTOR

## new

    my $credentials = Amazon::Credentials->new(%options);

or:

    my $credentials = Amazon::Credentials->new(\%options);

Discovers credentials and returns an `Amazon::Credentials` object.

If explicit access keys are supplied, provider discovery is skipped.

If `sso_role_name` and `sso_account_id` are supplied, the constructor
uses the SSO provider directly.

Otherwise the configured provider chain is searched until credentials are
found.

If no provider produces credentials, the constructor reports:

    no credentials available

The behavior of discovery failures is controlled by `raise_error` and
`print_error`.

## Constructor Options

### aws\_access\_key\_id / aws\_secret\_access\_key

Explicit AWS credentials.

Both values must be supplied together.

When both are present, normal credential discovery is bypassed.

A temporary session token may also be supplied with `token`.

    my $credentials = Amazon::Credentials->new(
    aws_access_key_id     => $access_key_id,
    aws_secret_access_key => $secret_access_key,
    token                 => $session_token,
    );

### cache

Controls whether credential values remain available after they are read.

Caching is enabled by default.

    my $credentials = Amazon::Credentials->new( cache => 0 );

When caching is disabled, each credential getter is effectively one-shot.
After a credential value is returned, the stored closure for that value is
replaced with one returning `undef`.

Disabling the cache does not perform credential rediscovery and does not
guarantee that Perl has erased the underlying string from process memory.

See ["SECURITY CONSIDERATIONS"](#security-considerations).

### debug

Enables debug logging.

    my $credentials = Amazon::Credentials->new(debug => 1);

The default logger writes debug messages to STDERR.

Sensitive request headers and credential-shaped data should be passed
through `sanitize` before being logged.

### imdsv2

Controls use of IMDSv2 for EC2 instance metadata credentials.

Valid values are:

- `preferred`

    The default.

    `Amazon::Credentials` attempts IMDSv2 first. If IMDSv2 token
    acquisition fails, it falls back to IMDSv1. If the instance metadata
    service still does not yield credentials, discovery continues with the
    remaining providers.

- `required`

    IMDSv2 token acquisition is required. Failure is fatal for the
    instance-role provider.

- `disabled`

    IMDSv2 token acquisition is skipped and instance metadata is accessed
    using IMDSv1.

For compatibility, numeric values are also accepted:

    0  => disabled
    1  => required

### logger

A logger object with a `debug` method.

    my $credentials = Amazon::Credentials->new( logger => $logger );

If no logger is supplied, a minimal logger writing to STDERR is used.

### order

An array reference specifying the order in which top-level credential
providers are searched.

    my $credentials = Amazon::Credentials->new( order => [qw(file env role)] );

The standard provider names are:

    env
    container
    role
    web_identity
    file

`order` controls precedence. It does not register providers.

If `plugins` is also supplied, every entry in `order` must also be
enabled by `plugins`.

### plugins

Restricts the top-level providers that may participate in credential
discovery.

    my $credentials = Amazon::Credentials->new( plugins => [qw(env file)] );

If `order` is not supplied, the order of the `plugins` list becomes the
search order.

If both `plugins` and `order` are supplied:

    plugins = availability
    order   = precedence

For example:

    my $credentials = Amazon::Credentials->new(
      plugins => [qw(env file role)],
      order   => [qw(file env role)]
    );

A provider selected by `order` but not enabled by `plugins` causes an
exception.

### profile

Selects an AWS profile.

    my $credentials = Amazon::Credentials->new( profile => 'sandbox', );

If `profile` is not supplied, `AWS_PROFILE` is used when present.

When a profile is explicitly selected and neither `order` nor `plugins`
has been supplied, discovery is restricted to the profile resolver.

This prevents unrelated environment, container, or instance-role
credentials from taking precedence over an explicitly requested profile.

### print\_error

Controls whether a discovery error is reported with `carp` when it is
not raised as an exception.

The default is true.

This option is mainly useful when `raise_error` is false.

### raise\_error

Controls whether credential discovery failures are raised with `croak`.

The default is true.

    my $credentials = Amazon::Credentials->new(
      raise_error => 0,
      print_error => 0,
    );

The most recent discovery error can then be retrieved with:

    my $error = $credentials->get_error;

### region

Provides a region to credential providers that require regional context.

    my $credentials = Amazon::Credentials->new( region => 'us-east-1', );

A selected provider or AWS profile may also establish the region.

Region is part of credential discovery context. Refreshing temporary
credentials does not cause `Amazon::Credentials` to rediscover or change
the facade's region.

### sso\_account\_id / sso\_role\_name

Compatibility options for directly obtaining AWS IAM Identity Center /
SSO role credentials without selecting a profile.

Both values are required together.

    my $credentials = Amazon::Credentials->new(
      sso_account_id => '123456789012',
      sso_role_name  => 'AdministratorAccess',
      sso_region     => 'us-east-1',
    );

The SSO provider searches the AWS SSO token cache for a usable access
token and requests role credentials for the requested account and role.

Profile-based SSO configuration is preferred for new applications.

### sso\_region

Region used for direct SSO credential retrieval.

If omitted, `region` is used when available.

### timeout

HTTP timeout in seconds used by the default user agent.

default: 3

### token

Session token associated with explicitly supplied temporary credentials.

### user\_agent

A custom HTTP user agent.

The object must provide:

    request($http_request)

and return an object implementing the response interface expected by
`Amazon::Credentials`.

The default is `Amazon::Credentials::HTTP::UserAgent`, which uses
`HTTP::Tiny`.

This option is primarily useful for testing or for applications requiring
custom HTTP behavior.

# CREDENTIAL ACCESS

## get\_aws\_access\_key\_id

    my $access_key_id = $credentials->get_aws_access_key_id;

Returns the AWS access key ID.

## get\_aws\_secret\_access\_key

    my $secret_access_key = $credentials->get_aws_secret_access_key;

Returns the AWS secret access key.

## get\_token

    my $session_token = $credentials->get_token;

Returns the AWS session token when temporary credentials are in use.

## get\_aws\_session\_token

Alias for `get_token`.

## credential\_keys

    my $keys = $credentials->credential_keys;

Returns a hash reference using standard AWS environment variable names:

    { AWS_ACCESS_KEY_ID     => ...,
      AWS_SECRET_ACCESS_KEY => ...,
      AWS_SESSION_TOKEN     => ...,
    }

`AWS_SESSION_TOKEN` is omitted when no session token is present.

## as\_string

    my $json = $credentials->as_string;

Returns `credential_keys` encoded as formatted JSON.

## format\_credentials

    my $text = $credentials->format_credentials("export %s=%s\n");

Formats each entry returned by `credential_keys` using the supplied
`sprintf` format.

The default format is:

    "%s %s\n"

# PROVIDER INFORMATION

## get\_provider

Returns the provider object that actually produced the credentials.

For profile-based credentials this is the resolved provider, not the
profile resolver.

For example, a profile containing `credential_process` produces a
`Provider::Process` object, while a profile containing `role_arn`
produces a `Provider::AssumeRole` object.

This distinction is important because credential refresh is delegated to
the credential-producing provider.

## get\_source

Returns the credential source reported by the selected provider.

## get\_region

Returns the region established during credential discovery.

# TEMPORARY CREDENTIALS AND REFRESH

## get\_expiration

    my $expiration = $credentials->get_expiration;

Returns the expiration timestamp reported by the selected provider.

Returns `undef` when there is no provider or the credentials do not
expire.

## set\_expiration

    $credentials->set_expiration($expiration);

Sets the expiration value on the selected provider.

This method is retained primarily for compatibility.

## is\_token\_expired

    if ( $credentials->is_token_expired ) {
      ...
    }

Returns true when the credential expiration time falls within the
configured expiration window.

The default window is five minutes.

A different window, in minutes, may be supplied:

    if ( $credentials->is_token_expired(10) ) {
      ...
    }

Credentials with no expiration are considered non-expiring.

## refresh\_token

    $credentials->refresh_token;

Refreshes temporary credentials using the selected provider.

Only providers that declare themselves refreshable may be refreshed.

The provider owns the refresh mechanism. Depending on the credential
source, refresh may mean:

- rerunning `credential_process`;
- requesting new SSO role credentials;
- refreshing an SSO access token before requesting role credentials;
- rereading a web identity token and calling STS;
- refreshing an assumed role, including refreshing its source provider when
necessary.

After the provider refreshes, the facade reloads the access key, secret
key, and session token from that provider. Expiration remains provider
state and is read through `get_expiration`.

Refresh does not rerun credential discovery, select a new provider, or
change the facade's discovery context.

Calling `refresh_token` for non-refreshable credentials raises:

credentials are not refreshable

# EXPLICIT CREDENTIAL MANAGEMENT

## set\_credentials

    $credentials->set_credentials(
      { aws_access_key_id     => $access_key_id,
        aws_secret_access_key => $secret_access_key,
        token                 => $session_token,
      }
    );

Replaces the credential tuple held by the facade.

`aws_access_key_id` and `aws_secret_access_key` are required.

The session token may be supplied as either:

    token
    aws_session_token

## reset\_credentials

    $credentials->reset_credentials;

Clears the credential values currently held by the facade.

This does not perform credential discovery.

# AWS PROFILE FEATURES

## Static Credentials

Static credentials may be read from AWS credentials and configuration
files.

## credential\_process

Profiles containing:

    credential_process = command ...

are resolved through the process provider.

The process output may contain temporary credentials and expiration
information. Refreshable process credentials are refreshed by running the
process again.

## AssumeRole

Profiles containing `role_arn` may obtain source credentials using
either:

    source_profile

or:

    credential_source

`source_profile` may resolve recursively.

The AssumeRole provider supports the profile options implemented by this
distribution, including role session name, external ID, and duration when
present.

MFA-assisted AssumeRole profiles using `mfa_serial` are supported.
See ["MFA Support"](#mfa-support).

## Web Identity

Web identity credentials may be discovered from the standard web identity
environment or from profile configuration.

The token file is reread when credentials are refreshed.

## AWS IAM Identity Center / SSO

Both modern `sso_session` profiles and legacy inline SSO profiles are
supported.

Modern configuration may use:

    [profile sandbox]
    sso_session = company
    sso_account_id = 123456789012
    sso_role_name = AdministratorAccess

    [sso-session company]
    sso_start_url = https://example.awsapps.com/start
    sso_region = us-east-1

Legacy inline profiles may use:

    [profile sandbox]
    sso_start_url = https://example.awsapps.com/start
    sso_region = us-east-1
    sso_account_id = 123456789012
    sso_role_name = AdministratorAccess

SSO access tokens are read from the AWS SSO cache.

When the cached access token can be refreshed, the SSO provider may
refresh it before obtaining new role credentials.

# EXPORTED FUNCTIONS

Nothing is exported by default.

The following function-shaped helpers may be imported explicitly.

## normalize\_arn

use Amazon::Credentials qw(normalize\_arn);

    my $iam_arn = normalize_arn($sts_arn);

Converts an STS assumed-role ARN:

    arn:aws:sts::123456789012:assumed-role/MyRole/session-name

to the corresponding IAM role ARN:

    arn:aws:iam::123456789012:role/MyRole

Other ARNs are returned unchanged.

The function may also be called as a method:

    my $iam_arn = $credentials->normalize_arn($sts_arn);

## get\_role\_credentials

    use Amazon::Credentials qw(get_role_credentials);

    my $role_credentials = get_role_credentials(
      account_id => '123456789012',
      role_name  => 'AdministratorAccess',
      region     => 'us-east-1',
    );

Compatibility interface for obtaining SSO role credentials directly.

The returned hash uses the field names returned by the AWS SSO
GetRoleCredentials API, including:

    accessKeyId
    secretAccessKey
    sessionToken
    expiration

New code will usually be simpler when SSO is configured through an AWS
profile and discovered through `Amazon::Credentials-`new>.

## set\_sso\_credentials

use Amazon::Credentials qw(set\_sso\_credentials);

    my $role_credentials = set_sso_credentials( 'AdministratorAccess', '123456789012', 'us-east-1', );

Compatibility interface for obtaining SSO role credentials and placing
them into:

    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN

The returned value is the raw SSO role credential hash.

This function mutates `%ENV`. New applications should generally prefer
constructing an `Amazon::Credentials` object.

# ERROR HANDLING

Credential discovery errors are retained in:

    $credentials->get_error

By default, discovery errors are raised as exceptions.

To inspect failures without raising an exception:

    my $credentials = Amazon::Credentials->new(
      raise_error => 0,
      print_error => 0,
    );

    if ( my $error = $credentials->get_error ) {
      ...
    }

Errors originating from an explicitly selected provider or an invalid
configuration may be fatal because continuing to another provider would
hide a configuration error.

# SECURITY CONSIDERATIONS

AWS credentials are secrets. The primary risk is not merely that a
process can retrieve them, but that credentials can leave the process
through logs, diagnostics, serialization, crash data, or other accidental
output.

## Credential Storage

Credential values held by `Amazon::Credentials` are captured in lexical
closures rather than stored as ordinary scalar object attributes.

As a result, ordinary object inspection such as:

    print Dumper($credentials);

shows code references rather than exposing the credential strings stored
inside those closures.

This reduces the chance of accidentally exposing credentials through
object serialization or diagnostic dumps.

It does not make process memory cryptographically secure.

## Caching

With the default:

    cache => 1

credential values remain available through their getters.

With:

    cache => 0

a credential getter clears its stored closure after returning the value.

This can reduce how long the facade retains an immediately accessible
credential value, but Perl does not guarantee that the memory previously
holding the string has been overwritten.

Do not treat `cache => 0` as secure memory erasure.

## Sanitizing Diagnostic Data

    my $safe = $credentials->sanitize($value);

`sanitize` recursively redacts credential-shaped and token-shaped values
from structures used for diagnostic logging.

It handles common sensitive keys including access keys, session tokens,
SSO tokens, authorization headers, web identity tokens, and IMDSv2
tokens.

`HTTP::Request` objects are cloned before sensitive headers are replaced.

`Amazon::Credentials::HTTP::Response` content is sanitized when it
contains structured JSON; opaque response content is replaced rather
than logged verbatim.

## Logging

Do not log access keys, secret keys, session tokens, SSO tokens,
authorization headers, web identity tokens, or metadata service tokens.

Use `sanitize` on request, response, and structured diagnostic data
before logging values that may contain credentials.

Debug mode must be enabled explicitly:

    Amazon::Credentials->new(debug => 1,);

The `DEBUG` environment variable does not implicitly enable debugging.

## IAM Permissions

Use credentials with the minimum permissions required by the
application.

Where practical, prefer short-lived role credentials over long-lived
static access keys.

# COMMAND LINE INTERFACE

The distribution installs:

    amazon-credentials

Use:

    amazon-credentials --help

for command-line usage information.

The command-line program provides access to the same credential discovery
and resolution mechanisms as the `Amazon::Credentials` API.

It is useful for obtaining credentials for shells, scripts, command-line
tools, and other applications that consume standard AWS environment
variables. In particular, it can resolve profile-based temporary
credentials, including assumed roles, SSO credentials, and MFA-assisted
`AssumeRole` profiles.

For example:

    eval "$(amazon-credentials --profile my-profile)"

or for an MFA-assisted profile:

    eval "$(amazon-credentials \
      --profile my-profile \
      --token 123456)"

# COMPATIBILITY

The provider architecture is a substantial internal change from earlier
releases.

The public `Amazon::Credentials` facade retains compatibility methods
where doing so does not conflict with the provider model, including
explicit credentials, SSO helper functions, credential getters, token
expiration helpers, provider ordering, and formatting methods.

The provider registration API and provider contract documented in
["ADDING CREDENTIAL PROVIDERS"](#adding-credential-providers) are supported extension points. Resolver
internals, concrete built-in provider implementations, and underscored
methods should not be treated as stable application interfaces unless
separately documented.

# INCOMPATIBILITIES

This module has not been tested on Windows.

# CONTRIBUTING

The project is hosted at:

    L<https://github.com/rlauer6/Amazon-Credentials>

Issues and pull requests are welcome.

# LICENSE AND COPYRIGHT

This module is free software. It may be used, redistributed, and/or
modified under the same terms as Perl itself.

# AUTHOR

Rob Lauer - <rclauer@gmail.com>

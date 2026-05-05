# Table of Contents

* [NAME](#name)
* [SYNOPSIS](#synopsis)
* [DESCRIPTION](#description)
  * [AWS\_EC2\_METADATA\_DISABLED](#aws\ec2\metadata\disabled)
* [VERSION](#version)
* [METHODS AND SUBROUTINES](#methods-and-subroutines)
  * [new](#new)
    * [options](#options)
  * [as\_string](#as\string)
  * [credential\_keys](#credential\keys)
  * [format\_credentials](#format\credentials)
  * [find\_credentials](#find\credentials)
  * [get\_creds\_from\_\*](#get\creds\from\\)
    * [get\_creds\_from\_container](#get\creds\from\container)
    * [get\_creds\_from\_web\_identity](#get\creds\from\web\identity)
    * [get\_creds\_from\_process](#get\creds\from\process)
    * [get\_creds\_from\_role](#get\creds\from\role)
  * [get\_default\_region](#get\default\region)
  * [get\_ec2\_credentials (deprecated)](#get\ec2\credentials-deprecated)
  * [is\_token\_expired](#is\token\expired)
  * [normalize\_arn](#normalize\arn)
  * [reset\_credentials](#reset\credentials)
  * [refresh\_token (deprecated)](#refresh\token-deprecated)
  * [refresh\_credentials()](#refresh\credentials)
  * [set\_credentials](#set\credentials)
* [SSO CREDENTIALS](#sso-credentials)
  * [get\_role\_credentials](#get\role\credentials)
  * [set\_sso\_credentials](#set\sso\credentials)
* [SETTERS/GETTERS](#settersgetters)
* [DIAGNOSTICS](#diagnostics)
* [CONFIGURATION AND ENVIRONMENT](#configuration-and-environment)
* [BUGS AND LIMITATIONS](#bugs-and-limitations)
* [DEPENDENCIES](#dependencies)
* [SECURITY CONSIDERATIONS](#security-considerations)
  * [How `Amazon::Credentials` Helps Prevent Exfiltration](#how-amazoncredentials-helps-prevent-exfiltration)
    * [Closure-Based Credential Storage](#closure-based-credential-storage)
    * [Caching and Memory](#caching-and-memory)
  * [Securing Your Logs](#securing-your-logs)
  * [Use Temporary Credentials](#use-temporary-credentials)
  * [Use Granular Credentials](#use-granular-credentials)
  * [Notes on Logging and Debug Mode](#notes-on-logging-and-debug-mode)
* [INCOMPATIBILITIES](#incompatibilities)
* [CONTRIBUTING](#contributing)
* [LICENSE AND COPYRIGHT](#license-and-copyright)
* [AUTHOR](#author)
# NAME

Amazon::Credentials - fetch Amazon credentials from file, environment or role

# SYNOPSIS

    my @order = qw( env file container role );
    my $creds = Amazon::Credentials->new( { order => \@order } );

CLI

    amazon-credentials --help

# DESCRIPTION

[![perl-Amazon-Credentials](https://github.com/rlauer6/Amazon-Credentials/actions/workflows/build.yml/badge.svg)](https://github.com/rlauer6/Amazon-Credentials/actions/workflows/build.yml)

`Amazon::Credentials` finds AWS credentials from a chain of providers,
searching in a configurable order until credentials are found. The default
search order is:

    environment => container => role => web_identity => file

The following credential sources are supported:

- **Environment** - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
and optionally `AWS_SESSION_TOKEN`.
- **Container** - ECS task roles via
`AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` (classic ECS), or any container
runtime that provides `AWS_CONTAINER_CREDENTIALS_FULL_URI` - including
Lambda execution roles, Fargate task roles, and EKS Pod Identity.
- **Instance role** - EC2 instance profile credentials via the IMDSv2
metadata endpoint (`http://169.254.169.254`). Respects
`AWS_EC2_METADATA_DISABLED`.
- **Web Identity** - OIDC/JWT federation via STS
`AssumeRoleWithWebIdentity`. Used by EKS IRSA (IAM Roles for Service
Accounts) and GitHub Actions. Requires `AWS_WEB_IDENTITY_TOKEN_FILE`
and `AWS_ROLE_ARN`.
- **File** - `~/.aws/credentials` and `~/.aws/config` profiles,
including credential\_process and SSO configurations.

You can control which sources are tried, and in what order, via the
`order` option in the constructor. See ["new"](#new).

This class also supports SSO credentials. See ["set\_sso\_credentials"](#set_sso_credentials)
and ["get\_role\_credentials"](#get_role_credentials) for details, or use the command line tool:

    amazon-credentials --role my-sso-role --account 01234567890

## AWS\_EC2\_METADATA\_DISABLED

`Amazon::Credentials` tries hard to find credentials, searching the
environment, ECS container endpoint, EC2 instance metadata, and credential
files in turn. In some situations - particularly local development or CI
environments where no metadata endpoint is reachable - this eagerness causes
an unwanted delay while the module waits for the metadata request to time out.

You have two options for dealing with this. The first is to set
`AWS_EC2_METADATA_DISABLED` to a true value, which disables the search for
role credentials via the EC2 instance metadata endpoint entirely. The second
is to reduce the timeout via the `timeout` constructor option (default is 3
seconds), which limits how long the module waits for the metadata endpoint to
respond:

    my $creds = Amazon::Credentials->new( timeout => 1 );

The preferred approach when your application is designed to run in a specific
environment is to pass an explicit `order` to the constructor, which avoids
the search entirely:

    my $creds = Amazon::Credentials->new( order => [qw(role)] );

The default credential search order is:

    environment => container => role => web_identity => file (profile)

# VERSION

This document refers to version 1.3.0 of
[Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials).

# METHODS AND SUBROUTINES

## new

    new( options );

    my $aws_creds = Amazon::Credential->new( { profile => 'sandbox', debug => 1 });

`options` is a hash of keys that represent various options you can
pass to the constructor to control how it will look for credentials.
Any of the options can also be retrieved using their corresponding
'get\_{option} method.

### options

- aws\_access\_key\_id

    AWS access key.

- aws\_secret\_access\_key

    AWS secret access key.

    _Note: If you pass the access keys in the constructor then the
    constructor will not look in other places for credentials._

- cache

    Boolean that controls whether credentials are retained in the object
    after being fetched. **Caching is enabled by default.**

    When caching is disabled, credentials are fetched on the first call to
    a getter and the closure for that credential is reset to undef
    immediately after the value is returned. Each subsequent getter call
    will re-fetch credentials. Use `credential_keys()` to retrieve the
    full credential tuple in a single operation without the values ever
    being split across multiple calls.

    Note that disabling the cache limits the window during which credential
    values are held in memory, but Perl makes no guarantees about when or
    whether that memory is actually cleared by the interpreter. See
    ["Caching and Memory"](#caching-and-memory) under ["SECURITY CONSIDERATIONS"](#security-considerations).

- container

    If the process is running in a container, this value will contain
    a string indicating the credential source. The class supports two
    forms of container credentials:

    **Relative URI** (classic ECS on EC2): credentials are fetched from
    the ECS container metadata endpoint using
    `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`:

        http://169.254.170.2/$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI

    **Full URI** (Lambda, Fargate, EKS Pod Identity): credentials are
    fetched from the full URL provided in
    `AWS_CONTAINER_CREDENTIALS_FULL_URI`. The URL must be `https://`,
    `http://127.x.x.x`, `http://[::1]`, or
    `http://169.254.170.23` (EKS Pod Identity agent). An optional
    authorization token may be provided via
    `AWS_CONTAINER_AUTHORIZATION_TOKEN` or
    `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`.

    The `container` metadata key in the returned credentials hash will
    be `'ECS'` for the relative URI form and `'full_uri'` for the full
    URI form.

- debug

    Set to true for verbose troubleshooting information. Set `logger` to
    a logger that implements a logging interface (ala
    [Log::Log4perl](https://metacpan.org/pod/Log%3A%3ALog4perl).

- env - Environment

    If there exists an environment variable $AWS\_PROFILE, then an attempt
    will be made to retrieve credentials from the credentials file using
    that profile, otherwise the class will for these environment variables
    to provide credentials.

        AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY
        AWS_SESSION_TOKEN

    _Note that when you set the environment variable AWS\_PROFILE, the
    order essentially is overridden and the class will look in your
    credential files (`~/.aws/config`, `~/.aws/credentials`) to resolve
    your credentials._

- file - Configuration Files

    - ~/.aws/config
    - ~/.aws/credentials

    The class will attempt to resolve credentials by interpretting the
    information in these two files. You can also specify a profile to use
    for looking up the credentials by passing it into the constructor or
    setting it the environment variable `AWS_PROFILE`.  If no profile is
    provided, the default credentials or the first profile found is used.

        my $aws_creds = Amazon::Credentials->new({ order => [qw/environment role file/] });

- imdsv2

    Boolean flag that causes `Amazon::Credentials` to use the IMDSv2
    protocol when retrieving instance role credentials from the EC2 metadata
    service. IMDSv2 uses a session-oriented approach requiring a token to be
    fetched before making metadata requests, providing stronger protection
    against SSRF attacks.

    Default: true

    AWS recommends IMDSv2 for all EC2 workloads. IMDSv1 can be disabled at
    the instance or account level as a security hardening measure, in which
    case this option must be enabled for instance role credential retrieval
    to succeed.

- logger

    Pass in your own logger that has a `debug()` method.  Otherwise the
    default logger will output debug messages to STDERR.
    &#x3d;item order

    An array reference containing tokens that specifies the order in which the class will
    search for credentials.

    default:  env, role, container, file

    Example:

        my $creds = Amazon::Credentials->new( { order => [ qw/file env role/] });

- print\_error

    Whether to print the error if no credenials are found. `raise_error`
    implies `print_error`.

    default: true

- profile

    The profile name in the configuration file (`~/.aws/config` or
    `~/.aws/credentials`).

        my $aws_creds = Amazon::Credentials->new({ profile => 'sandbox' });

    The class will also look for the environment variable `AWS_PROFILE`,
    so you can invoke your script like this:

        $ AWS_PROFILE=sandbox my-script.pl

- raise\_error

    Whether to raise an error if credentials are not found.

    default: true

- region

    Default region. The class will attempt to find the region in either
    the configuration files or the instance unless you specify the region
    in the constructor.

- role - Instance Role

    The class will use the
    _http://169.254.169.254/latest/meta-data/iam/security-credential_ URL
    to look for an instance role and credentials.

    Credentials returned by accessing the meta-data include a token that
    should be passed to Amazon APIs along with the access key and secret.
    That token has an expiration and should be refreshed before it
    expires.

        if ( $aws_creds->is_token_expired() ) {
          $aws_creds->refresh_token()
        }

- timeout

    When looking for credentials in metadata URLs, this parameter
    specifies the timeout value in seconds for HTTP metadata sevice
    requests.

    default: 3s

- user\_agent

    Pass in your own user agent, otherwise `Amazon::Credentials::HTTP::UserAgent`
    (backed by `HTTP::Tiny`) will be used. The object must implement a `request`
    method accepting an `HTTP::Request` object and returning a response object
    with `content`, `content_type`, `is_success`, `code`, and `message` methods.
    Probably only useful to override for testing purposes.

## as\_string

    as_string()

Returns the credentials as a JSON encode string.

## credential\_keys

    my $credential_keys = $creds->credential_keys;

Return a hash reference containing the credential keys with standard
key names. Note that the session token will only be present in the
hash for temporary credentials.

- AWS\_ACCESS\_KEY\_ID
- AWS\_SECRET\_ACCESS\_KEY
- AWS\_SESSION\_TOKEN

## format\_credentials

    format_credentials(format-string)

Returns the credentials as a formatted string.  The &lt;format> argument
allows you to include a format string that will be used to output each
of the credential parts.

    format("export %s=%s\n");

The default format is a "%s %s\\n".

## find\_credentials

    find_credentials( option => value, ...);

You normally don't want to use this method. It's automatically invoked
by the constructor if you don't pass in any credentials. Accepts a
hash or hash reference consisting of keys (`order` or `profile`) in
the same manner as the constructor.

## get\_creds\_from\_\*

These methods are called internally when the `new` constructor is
invoked. You should never need to call these methods. All of these
methods will return a hash of credential information and metadata
described below.

- aws\_access\_key\_id

    The AWS access key.

- aws\_secret\_access\_key

    The AWS secret key.

- token

    Security token used with access keys.

- expiration

    Token expiration date.

- role

    IAM role if available.

- source

    The source from which the credentials were found. 

    - IAM - retrieved from container or instance role
    - container - `'ECS'` if retrieved via `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`;
    `'full_uri'` if retrieved via `AWS_CONTAINER_CREDENTIALS_FULL_URI`
    - web\_identity - retrieved via STS AssumeRoleWithWebIdentity
    - file - retrieved from file
    - process - retrieved from an external process
    - ENV - retrieved from environment

### get\_creds\_from\_container

    get_creds_from_container()

Retrieves credentials from the container credential endpoint. Supports
two mechanisms, tried in this order:

**Relative URI** - if `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` is set,
credentials are fetched from:

    http://169.254.170.2/$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI

**Full URI** - if `AWS_CONTAINER_CREDENTIALS_FULL_URI` is set, that URL
is used directly. Covers Lambda execution roles, Fargate task roles, and
EKS Pod Identity. An authorization token is added automatically if
`AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE` or
`AWS_CONTAINER_AUTHORIZATION_TOKEN` is set in the environment.

Returns an empty hash if neither environment variable is set.

### get\_creds\_from\_web\_identity

    get_creds_from_web_identity()

Retrieves temporary credentials by exchanging an OIDC/JWT web identity
token for AWS credentials via STS `AssumeRoleWithWebIdentity`. This is
the credential mechanism used by EKS IRSA (IAM Roles for Service
Accounts) and GitHub Actions OIDC federation.

Required environment variables:

- `AWS_WEB_IDENTITY_TOKEN_FILE`

    Path to a file containing the OIDC/JWT token.

- `AWS_ROLE_ARN`

    ARN of the IAM role to assume.

Optional:

- `AWS_ROLE_SESSION_NAME`

    A name for the assumed role session. Defaults to
    `amazon-credentials-session`.

The STS call is made without AWS request signing - the OIDC token
itself authenticates the request, resolving the chicken-and-egg problem
of needing credentials to obtain credentials. The regional STS endpoint
is used when `AWS_DEFAULT_REGION` or `AWS_REGION` is set; otherwise
the global `sts.amazonaws.com` endpoint is used.

Returns an empty hash if the required environment variables are not set,
if the token file cannot be read, or if the STS call fails.

### get\_creds\_from\_process

    get_creds_from_process(process)

Retrieves credentials from a helper process defined in the config
file. Returns the credentials tuple.

### get\_creds\_from\_role

    get_creds_from_role()

Returns a hash, possibly containing access keys and a token.

## get\_default\_region

Returns the region of the currently running instance or container.
The constructor will set the region to this value unless you set your
own `region` value. Use `get_region` to retrieve the value after
instantiation or you can call this method again and it will make a
second call to retrieve the instance metadata.

## get\_ec2\_credentials (deprecated)

See ["find\_credentials"](#find_credentials)

## is\_token\_expired

    is_token_expired( window-interval )

Returns true if the token is about to expire (or is
expired). `window-interval` is the time in minutes before the actual
expiration time that the method should consider the token expired.
The default is 5 minutes.  Amazon states that new credentials will be
available _at least_ 5 minutes before a token expires.

## normalize\_arn

    normalize_arn( arn )

    # as an exported function
    use Amazon::Credentials qw(normalize_arn);
    my $iam_arn = normalize_arn($sts_arn);

    # or as a method
    my $iam_arn = $creds->normalize_arn($sts_arn);

Converts an STS assumed-role ARN to its equivalent IAM role ARN.

    arn:aws:sts::123456789:assumed-role/my-role/session-name
      => arn:aws:iam::123456789:role/my-role

This is useful when an ARN obtained from `GetCallerIdentity` needs to be
passed to IAM APIs such as `SimulatePrincipalPolicy` which require an IAM
ARN and will reject STS assumed-role ARNs. Non-assumed-role ARNs (IAM users,
IAM roles) are returned unchanged.

## reset\_credentials

By default this method will remove credentials from the cache if you
pass a false or no value. Passing a true value will refresh your
credentials from the original source (equivalent to calling
`set_credentials`).

## refresh\_token (deprecated)

use `refresh_credentials()`

## refresh\_credentials()

Retrieves a fresh set of IAM credentials.

    if ( $creds->is_token_expired ) {
      $creds->refresh_token()
    }

## set\_credentials

Looks for your credentials according to the order specified by the
`order` attribute passed in the constructor and stores the
credentials in the cache.

_Note that you should never have to call
this method. If you call this method it will ignore your cache
setting!_

# SSO CREDENTIALS

You can retrieve your SSO credentials after logging in using the
`sso_set_credentials` or `get_role_credentials` methods.

After logging in using your SSO credentials...

    aws sso login

...call one of the methods below to retrieve your credentials.

## get\_role\_credentials

    get_role_credentials( options )

`options` is a hash (not reference) of options

- role\_name => role name (required)
- account\_id => AWS account id (required)
- region => AWS region where SSO has been provisioned

    default: $ENV{AWS\_REGION}, $ENV{AWS\_DEFAULT\_REGION}, us-east-1

## set\_sso\_credentials

    set_sso_options(role-name, account-id, region)

Calls `get_role_credentials` and set AWS credenital environment
variables. Region is optional, all other parameters are required.

    use Amazon::Credentials qw(set_sso_credentials)

    set_sso_credentials(@ENV{qw(AWS_ROLE_NAME AWS_ACCOUNT_ID)});

    my $credentials = Amazon::Credentials->new;

# SETTERS/GETTERS

All of the options described in the new method can be accessed by a
_getter_ or set using a _setter_ of the same name.

Example:

    $creds->set_cache(0);

# DIAGNOSTICS

Set the `debug` option when you instantiate a [Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials)
object to output debug and diagnostic messages.

# CONFIGURATION AND ENVIRONMENT

The module will recognize several AWS specific environment variables
described throughout this documentation.

- AWS\_ACCESS\_KEY\_ID
- AWS\_SECRET\_ACCESS\_KEY
- AWS\_SESSION\_TOKEN
- AWS\_REGION
- AWS\_DEFAULT\_REGION
- AWS\_CONTAINER\_CREDENTIALS\_RELATIVE\_URI
- AWS\_CONTAINER\_CREDENTIALS\_FULL\_URI
- AWS\_CONTAINER\_AUTHORIZATION\_TOKEN
- AWS\_CONTAINER\_AUTHORIZATION\_TOKEN\_FILE
- AWS\_WEB\_IDENTITY\_TOKEN\_FILE
- AWS\_ROLE\_ARN
- AWS\_ROLE\_SESSION\_NAME

# BUGS AND LIMITATIONS

[Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials) will **not** attempt to retrieve temporary
credentials for profiles that specify a role. If for example you
define a role in your credentials file thusly:

    [developer]

     role_arn = arn:aws:iam::123456789012:role/developer-access-role
     source_profile = dev

The module will not return credentials for the _developer_
profile. While it would be theoretically possible to return those
credentials, in order to assume a role, one needs credentials (chicken
and egg problem).

Note that `get_creds_from_web_identity` resolves this problem for
OIDC-federated environments (EKS IRSA, GitHub Actions) by calling STS
`AssumeRoleWithWebIdentity`, which does not require AWS signing - the
OIDC token authenticates the request directly.

# DEPENDENCIES

Lower versions of these modules may be acceptable.

    'Class::Accessor::Fast' => '0.31'
    'Config::Tiny'          => '2.28'
    'File::HomeDir'         => '1.00'
    'HTTP::Request'         => '6.00'
    'HTTP::Tiny'            => '0.088'
    'JSON::PP'              => '4.16'
    'List::Util'            => '1.5'
    'Net::SSLeay'           => '0'
    'IO::Socket::SSL'       => '0'
    'POSIX::strptime'       => '0.13'

...and possibly others

# SECURITY CONSIDERATIONS

The security concern around your credentials is not that they can be
retrieved and viewed - any process that compromises your environment
can use the same discovery methods this module does. If your
environment is compromised, an actor can resolve your credentials the
same way this module does. The real threat is **exfiltration**: your
credentials escaping your environment through logs, debug output,
serialized objects, or core dumps.

**Always take precautions to prevent accidental exfiltration of your
credentials.**

## How `Amazon::Credentials` Helps Prevent Exfiltration

### Closure-Based Credential Storage

Starting with version _1.3.0_, credentials are never stored as plain
scalar attributes on the object. Instead they are captured in Perl
closures. The object holds a code reference for each credential value;
calling it returns the credential. The values themselves live only in
the closure's lexical scope and are invisible to serialization:

    use Data::Dumper;
    my $creds = Amazon::Credentials->new;
    print Dumper $creds;
    # _access_key_id     => sub { "DUMMY" },
    # _secret_access_key => sub { "DUMMY" },
    # _session_token     => sub { "DUMMY" },

`Dumper`, `JSON::PP::encode_json`, exception stack traces, and
similar introspection tools will show only opaque code references -
never the credential values. This replaces the previous
encryption-based approach, which was both heavier (requiring
[Crypt::CBC](https://metacpan.org/pod/Crypt%3A%3ACBC) and [Crypt::Cipher::AES](https://metacpan.org/pod/Crypt%3A%3ACipher%3A%3AAES)) and weaker (the passkey lived
on the same object as the ciphertext unless you explictly sourced your
passkey from an external process).

### Caching and Memory

Disabling the cache with `cache => 0` means credentials are
fetched on first use and the closures are reset to undef immediately
after each getter call. This limits the window during which a live
value exists in memory.

    my $credentials = Amazon::Credentials->new( cache => 0 );

However, **Perl makes no guarantees about when or whether memory
containing a sensitive value is actually cleared**. The interpreter
may retain a copy of the string in freed memory, in a copy-on-write
buffer, or in an arena waiting to be reclaimed. Disabling the cache
reduces the lifetime of credentials in the object, but it is not a
substitute for running in a properly secured environment.

If you need the credential tuple at once without it ever being split
across multiple getter calls, use `credential_keys()`:

    my $keys = $creds->credential_keys;
    # { aws_access_key_id => ..., aws_secret_access_key => ..., token => ... }

- Option 2 - Remove them manually after use

    Call `reset_credentials()` with a false value after fetching
    credentials or after they are used by downstream processes. Call it
    with a true value to regenerate them.

- Using Multiple Instances of Amazon::Credentials

    You may need to assume a role using initial credentials. In this case
    you can use multiple instances of [Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials).

        # 1. retrieve SSO credentials
        my $sso_credentials = Amazon::Credentials->new(
          sso_role_name  => 'developer',
          sso_account_id => '01234567890'
        );

        # 2. assume a role in another account
        my $role_arn          = 'arn:aws:iam::09876543210:role/Route53AccountAccessRole';
        my $role_session_name = "route53-role-$PID";

        my $sts = Amazon::API::STS->new( credentials => $sso_credentials );

        my $assume_role_result = $sts->AssumeRole(
          { RoleArn         => $role_arn,
            RoleSessionName => $role_session_name,
          }
        );

        my $assumed = $assume_role_result->{AssumeRoleResult}{Credentials};

        # 3. create new credentials for assumed role
        my $role_credentials = Amazon::Credentials->new(
          aws_access_key_id     => $assumed->{AccessKeyId},
          aws_secret_access_key => $assumed->{SecretAccessKey},
          expiration            => $assumed->{Expiration},
          token                 => $assumed->{SessionToken},
        );

        # 4. make a call using the assumed role
        my $rt53 = Amazon::API::Route53->new( credentials => $role_credentials );

        my $response = $rt53->ListTagsForResources(
          { ResourceType => 'hostedzone',
            ResourceIds  => \@zone_ids,
          }
        );

## Securing Your Logs

To troubleshoot this module you can pass a `debug` flag that writes
diagnostic information to STDERR. Because credentials are stored as
closures, they cannot appear in debug output produced by
[Data::Dumper](https://metacpan.org/pod/Data%3A%3ADumper) or similar tools - the object dump shows only code
references. You should still be careful with any application-level
logging that explicitly calls the getter methods and logs their return
values.

## Use Temporary Credentials

Use temporary credentials with short expiration times whenever
possible. [Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials) provides methods to check expiration
and refresh credentials when they have expired.

    if ( $credentials->is_token_expired ) {
      $credentials->refresh_token;
    }

## Use Granular Credentials

Consider the APIs you are calling. If all you need is access to a
single S3 bucket, use credentials scoped to that bucket only. IAM
permissions can be quite specific about what resources credentials
can access and from where.

## Notes on Logging and Debug Mode

Starting with version _1.1.0_, [Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials) does **not**
use the `DEBUG` environment variable to enable debug output. You must
explicitly pass `debug => 1` to the constructor. This prevents
upstream modules that set `DEBUG` from inadvertently triggering debug
mode in [Amazon::Credentials](https://metacpan.org/pod/Amazon%3A%3ACredentials).

# INCOMPATIBILITIES

This module has not been tested on Windows OS.

# CONTRIBUTING

You can find this project on GitHub at
[https://github.com/rlauer6/perl-Amazon-Credentials](https://github.com/rlauer6/perl-Amazon-Credentials).  PRs are always
welcomed!

# LICENSE AND COPYRIGHT

This module is free software. It may be used, redistributed and/or
modified under the same terms as Perl itself.

# AUTHOR

Rob Lauer - <rlauer6@comcast.net>

<a id="table-of-contents" class="anchor" aria-label="Permalink: Table of Contents" href="#table-of-contents"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">Table of Contents</h1>
<ul>
<li><a href="#name">NAME</a></li>
<li><a href="#synopsis">SYNOPSIS</a></li>
<li>
<a href="#description">DESCRIPTION</a>
<ul>
<li><a href="#aws%5Cec2%5Cmetadata%5Cdisabled">AWS_EC2_METADATA_DISABLED</a></li>
</ul>
</li>
<li><a href="#version">VERSION</a></li>
<li>
<a href="#methods-and-subroutines">METHODS AND SUBROUTINES</a>
<ul>
<li>
<a href="#new">new</a>
<ul>
<li><a href="#options">options</a></li>
</ul>
</li>
<li><a href="#as%5Cstring">as_string</a></li>
<li><a href="#credential%5Ckeys">credential_keys</a></li>
<li><a href="#format%5Ccredentials">format_credentials</a></li>
<li><a href="#find%5Ccredentials">find_credentials</a></li>
<li>
<a href="#get%5Ccreds%5Cfrom%5C">get_creds_from_*</a>
<ul>
<li><a href="#get%5Ccreds%5Cfrom%5Ccontainer">get_creds_from_container</a></li>
<li><a href="#get%5Ccreds%5Cfrom%5Cweb%5Cidentity">get_creds_from_web_identity</a></li>
<li><a href="#get%5Ccreds%5Cfrom%5Cprocess">get_creds_from_process</a></li>
<li><a href="#get%5Ccreds%5Cfrom%5Crole">get_creds_from_role</a></li>
</ul>
</li>
<li><a href="#get%5Cdefault%5Cregion">get_default_region</a></li>
<li><a href="#get%5Cec2%5Ccredentials-deprecated">get_ec2_credentials (deprecated)</a></li>
<li><a href="#is%5Ctoken%5Cexpired">is_token_expired</a></li>
<li><a href="#normalize%5Carn">normalize_arn</a></li>
<li><a href="#reset%5Ccredentials">reset_credentials</a></li>
<li><a href="#refresh%5Ctoken-deprecated">refresh_token (deprecated)</a></li>
<li><a href="#refresh%5Ccredentials">refresh_credentials()</a></li>
<li><a href="#set%5Ccredentials">set_credentials</a></li>
</ul>
</li>
<li>
<a href="#sso-credentials">SSO CREDENTIALS</a>
<ul>
<li><a href="#get%5Crole%5Ccredentials">get_role_credentials</a></li>
<li><a href="#set%5Csso%5Ccredentials">set_sso_credentials</a></li>
</ul>
</li>
<li><a href="#settersgetters">SETTERS/GETTERS</a></li>
<li><a href="#diagnostics">DIAGNOSTICS</a></li>
<li><a href="#configuration-and-environment">CONFIGURATION AND ENVIRONMENT</a></li>
<li><a href="#bugs-and-limitations">BUGS AND LIMITATIONS</a></li>
<li><a href="#dependencies">DEPENDENCIES</a></li>
<li>
<a href="#security-considerations">SECURITY CONSIDERATIONS</a>
<ul>
<li>
<a href="#how-amazoncredentials-helps-prevent-exfiltration">How <code>Amazon::Credentials</code> Helps Prevent Exfiltration</a>
<ul>
<li><a href="#closure-based-credential-storage">Closure-Based Credential Storage</a></li>
<li><a href="#caching-and-memory">Caching and Memory</a></li>
</ul>
</li>
<li><a href="#securing-your-logs">Securing Your Logs</a></li>
<li><a href="#use-temporary-credentials">Use Temporary Credentials</a></li>
<li><a href="#use-granular-credentials">Use Granular Credentials</a></li>
<li><a href="#notes-on-logging-and-debug-mode">Notes on Logging and Debug Mode</a></li>
</ul>
</li>
<li><a href="#incompatibilities">INCOMPATIBILITIES</a></li>
<li><a href="#contributing">CONTRIBUTING</a></li>
<li><a href="#license-and-copyright">LICENSE AND COPYRIGHT</a></li>
<li><a href="#author">AUTHOR</a></li>
</ul>
<a id="name" class="anchor" aria-label="Permalink: NAME" href="#name"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">NAME</h1>
<p>Amazon::Credentials - fetch Amazon credentials from file, environment or role</p>
<a id="synopsis" class="anchor" aria-label="Permalink: SYNOPSIS" href="#synopsis"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">SYNOPSIS</h1>
<pre><code>my @order = qw( env file container role );
my $creds = Amazon::Credentials-&gt;new( { order =&gt; \@order } );
</code></pre>
<p>CLI</p>
<pre><code>amazon-credentials --help
</code></pre>
<a id="description" class="anchor" aria-label="Permalink: DESCRIPTION" href="#description"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">DESCRIPTION</h1>
<p><a href="https://github.com/rlauer6/Amazon-Credentials/actions/workflows/build.yml"><img src="https://github.com/rlauer6/Amazon-Credentials/actions/workflows/build.yml/badge.svg" alt="perl-Amazon-Credentials" style="max-width: 100%;"></a></p>
<p><code>Amazon::Credentials</code> finds AWS credentials from a chain of providers,
searching in a configurable order until credentials are found. The default
search order is:</p>
<pre><code>environment =&gt; container =&gt; role =&gt; web_identity =&gt; file
</code></pre>
<p>The following credential sources are supported:</p>
<ul>
<li>
<strong>Environment</strong> - <code>AWS_ACCESS_KEY_ID</code>, <code>AWS_SECRET_ACCESS_KEY</code>,
and optionally <code>AWS_SESSION_TOKEN</code>.</li>
<li>
<strong>Container</strong> - ECS task roles via
<code>AWS_CONTAINER_CREDENTIALS_RELATIVE_URI</code> (classic ECS), or any container
runtime that provides <code>AWS_CONTAINER_CREDENTIALS_FULL_URI</code> - including
Lambda execution roles, Fargate task roles, and EKS Pod Identity.</li>
<li>
<strong>Instance role</strong> - EC2 instance profile credentials via the IMDSv2
metadata endpoint (<code>http://169.254.169.254</code>). Respects
<code>AWS_EC2_METADATA_DISABLED</code>.</li>
<li>
<strong>Web Identity</strong> - OIDC/JWT federation via STS
<code>AssumeRoleWithWebIdentity</code>. Used by EKS IRSA (IAM Roles for Service
Accounts) and GitHub Actions. Requires <code>AWS_WEB_IDENTITY_TOKEN_FILE</code>
and <code>AWS_ROLE_ARN</code>.</li>
<li>
<strong>File</strong> - <code>~/.aws/credentials</code> and <code>~/.aws/config</code> profiles,
including credential_process and SSO configurations.</li>
</ul>
<p>You can control which sources are tried, and in what order, via the
<code>order</code> option in the constructor. See <a href="#new">"new"</a>.</p>
<p>This class also supports SSO credentials. See <a href="#set_sso_credentials">"set_sso_credentials"</a>
and <a href="#get_role_credentials">"get_role_credentials"</a> for details, or use the command line tool:</p>
<pre><code>amazon-credentials --role my-sso-role --account 01234567890
</code></pre>
<a id="aws_ec2_metadata_disabled" class="anchor" aria-label="Permalink: AWS_EC2_METADATA_DISABLED" href="#aws_ec2_metadata_disabled"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">AWS_EC2_METADATA_DISABLED</h2>
<p><code>Amazon::Credentials</code> tries hard to find credentials, searching the
environment, ECS container endpoint, EC2 instance metadata, and credential
files in turn. In some situations - particularly local development or CI
environments where no metadata endpoint is reachable - this eagerness causes
an unwanted delay while the module waits for the metadata request to time out.</p>
<p>You have two options for dealing with this. The first is to set
<code>AWS_EC2_METADATA_DISABLED</code> to a true value, which disables the search for
role credentials via the EC2 instance metadata endpoint entirely. The second
is to reduce the timeout via the <code>timeout</code> constructor option (default is 3
seconds), which limits how long the module waits for the metadata endpoint to
respond:</p>
<pre><code>my $creds = Amazon::Credentials-&gt;new( timeout =&gt; 1 );
</code></pre>
<p>The preferred approach when your application is designed to run in a specific
environment is to pass an explicit <code>order</code> to the constructor, which avoids
the search entirely:</p>
<pre><code>my $creds = Amazon::Credentials-&gt;new( order =&gt; [qw(role)] );
</code></pre>
<p>The default credential search order is:</p>
<pre><code>environment =&gt; container =&gt; role =&gt; web_identity =&gt; file (profile)
</code></pre>
<a id="version" class="anchor" aria-label="Permalink: VERSION" href="#version"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">VERSION</h1>
<p>This document refers to version 1.3.1 of
<a href="https://metacpan.org/pod/Amazon%3A%3ACredentials" rel="nofollow">Amazon::Credentials</a>.</p>
<a id="methods-and-subroutines" class="anchor" aria-label="Permalink: METHODS AND SUBROUTINES" href="#methods-and-subroutines"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">METHODS AND SUBROUTINES</h1>
<a id="new" class="anchor" aria-label="Permalink: new" href="#new"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">new</h2>
<pre><code>new( options );

my $aws_creds = Amazon::Credential-&gt;new( { profile =&gt; 'sandbox', debug =&gt; 1 });
</code></pre>
<p><code>options</code> is a hash of keys that represent various options you can
pass to the constructor to control how it will look for credentials.
Any of the options can also be retrieved using their corresponding
'get_{option} method.</p>
<a id="options" class="anchor" aria-label="Permalink: options" href="#options"><span aria-hidden="true" class="octicon octicon-link"></span></a><h3 class="heading-element">options</h3>
<ul>
<li>
<p>aws_access_key_id</p>
<p>AWS access key.</p>
</li>
<li>
<p>aws_secret_access_key</p>
<p>AWS secret access key.</p>
<p><em>Note: If you pass the access keys in the constructor then the
constructor will not look in other places for credentials.</em></p>
</li>
<li>
<p>cache</p>
<p>Boolean that controls whether credentials are retained in the object
after being fetched. <strong>Caching is enabled by default.</strong></p>
<p>When caching is disabled, credentials are fetched on the first call to
a getter and the closure for that credential is reset to undef
immediately after the value is returned. Each subsequent getter call
will re-fetch credentials. Use <code>credential_keys()</code> to retrieve the
full credential tuple in a single operation without the values ever
being split across multiple calls.</p>
<p>Note that disabling the cache limits the window during which credential
values are held in memory, but Perl makes no guarantees about when or
whether that memory is actually cleared by the interpreter. See
<a href="#caching-and-memory">"Caching and Memory"</a> under <a href="#security-considerations">"SECURITY CONSIDERATIONS"</a>.</p>
</li>
<li>
<p>container</p>
<p>If the process is running in a container, this value will contain
a string indicating the credential source. The class supports two
forms of container credentials:</p>
<p><strong>Relative URI</strong> (classic ECS on EC2): credentials are fetched from
the ECS container metadata endpoint using
<code>AWS_CONTAINER_CREDENTIALS_RELATIVE_URI</code>:</p>
<pre><code>  http://169.254.170.2/$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
</code></pre>
<p><strong>Full URI</strong> (Lambda, Fargate, EKS Pod Identity): credentials are
fetched from the full URL provided in
<code>AWS_CONTAINER_CREDENTIALS_FULL_URI</code>. The URL must be <code>https://</code>,
<code>http://127.x.x.x</code>, <code>http://[::1]</code>, or
<code>http://169.254.170.23</code> (EKS Pod Identity agent). An optional
authorization token may be provided via
<code>AWS_CONTAINER_AUTHORIZATION_TOKEN</code> or
<code>AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE</code>.</p>
<p>The <code>container</code> metadata key in the returned credentials hash will
be <code>'ECS'</code> for the relative URI form and <code>'full_uri'</code> for the full
URI form.</p>
</li>
<li>
<p>debug</p>
<p>Set to true for verbose troubleshooting information. Set <code>logger</code> to
a logger that implements a logging interface (ala
<a href="https://metacpan.org/pod/Log%3A%3ALog4perl" rel="nofollow">Log::Log4perl</a>.</p>
</li>
<li>
<p>env - Environment</p>
<p>If there exists an environment variable $AWS_PROFILE, then an attempt
will be made to retrieve credentials from the credentials file using
that profile, otherwise the class will for these environment variables
to provide credentials.</p>
<pre><code>  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN
</code></pre>
<p><em>Note that when you set the environment variable AWS_PROFILE, the
order essentially is overridden and the class will look in your
credential files (<code>~/.aws/config</code>, <code>~/.aws/credentials</code>) to resolve
your credentials.</em></p>
</li>
<li>
<p>file - Configuration Files</p>
<ul>
<li>~/.aws/config</li>
<li>~/.aws/credentials</li>
</ul>
<p>The class will attempt to resolve credentials by interpretting the
information in these two files. You can also specify a profile to use
for looking up the credentials by passing it into the constructor or
setting it the environment variable <code>AWS_PROFILE</code>.  If no profile is
provided, the default credentials or the first profile found is used.</p>
<pre><code>  my $aws_creds = Amazon::Credentials-&gt;new({ order =&gt; [qw/environment role file/] });
</code></pre>
</li>
<li>
<p>imdsv2</p>
<p>Boolean flag that causes <code>Amazon::Credentials</code> to use the IMDSv2
protocol when retrieving instance role credentials from the EC2 metadata
service. IMDSv2 uses a session-oriented approach requiring a token to be
fetched before making metadata requests, providing stronger protection
against SSRF attacks.</p>
<p>Default: true</p>
<p>AWS recommends IMDSv2 for all EC2 workloads. IMDSv1 can be disabled at
the instance or account level as a security hardening measure, in which
case this option must be enabled for instance role credential retrieval
to succeed.</p>
</li>
<li>
<p>logger</p>
<p>Pass in your own logger that has a <code>debug()</code> method.  Otherwise the
default logger will output debug messages to STDERR.
=item order</p>
<p>An array reference containing tokens that specifies the order in which the class will
search for credentials.</p>
<p>default:  env, role, container, file</p>
<p>Example:</p>
<pre><code>  my $creds = Amazon::Credentials-&gt;new( { order =&gt; [ qw/file env role/] });
</code></pre>
</li>
<li>
<p>print_error</p>
<p>Whether to print the error if no credenials are found. <code>raise_error</code>
implies <code>print_error</code>.</p>
<p>default: true</p>
</li>
<li>
<p>profile</p>
<p>The profile name in the configuration file (<code>~/.aws/config</code> or
<code>~/.aws/credentials</code>).</p>
<pre><code>  my $aws_creds = Amazon::Credentials-&gt;new({ profile =&gt; 'sandbox' });
</code></pre>
<p>The class will also look for the environment variable <code>AWS_PROFILE</code>,
so you can invoke your script like this:</p>
<pre><code>  $ AWS_PROFILE=sandbox my-script.pl
</code></pre>
</li>
<li>
<p>raise_error</p>
<p>Whether to raise an error if credentials are not found.</p>
<p>default: true</p>
</li>
<li>
<p>region</p>
<p>Default region. The class will attempt to find the region in either
the configuration files or the instance unless you specify the region
in the constructor.</p>
</li>
<li>
<p>role - Instance Role</p>
<p>The class will use the
<em><a href="http://169.254.169.254/latest/meta-data/iam/security-credential" rel="nofollow">http://169.254.169.254/latest/meta-data/iam/security-credential</a></em> URL
to look for an instance role and credentials.</p>
<p>Credentials returned by accessing the meta-data include a token that
should be passed to Amazon APIs along with the access key and secret.
That token has an expiration and should be refreshed before it
expires.</p>
<pre><code>  if ( $aws_creds-&gt;is_token_expired() ) {
    $aws_creds-&gt;refresh_token()
  }
</code></pre>
</li>
<li>
<p>timeout</p>
<p>When looking for credentials in metadata URLs, this parameter
specifies the timeout value in seconds for HTTP metadata sevice
requests.</p>
<p>default: 3s</p>
</li>
<li>
<p>user_agent</p>
<p>Pass in your own user agent, otherwise <code>Amazon::Credentials::HTTP::UserAgent</code>
(backed by <code>HTTP::Tiny</code>) will be used. The object must implement a <code>request</code>
method accepting an <code>HTTP::Request</code> object and returning a response object
with <code>content</code>, <code>content_type</code>, <code>is_success</code>, <code>code</code>, and <code>message</code> methods.
Probably only useful to override for testing purposes.</p>
</li>
</ul>
<a id="as_string" class="anchor" aria-label="Permalink: as_string" href="#as_string"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">as_string</h2>
<pre><code>as_string()
</code></pre>
<p>Returns the credentials as a JSON encode string.</p>
<a id="credential_keys" class="anchor" aria-label="Permalink: credential_keys" href="#credential_keys"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">credential_keys</h2>
<pre><code>my $credential_keys = $creds-&gt;credential_keys;
</code></pre>
<p>Return a hash reference containing the credential keys with standard
key names. Note that the session token will only be present in the
hash for temporary credentials.</p>
<ul>
<li>AWS_ACCESS_KEY_ID</li>
<li>AWS_SECRET_ACCESS_KEY</li>
<li>AWS_SESSION_TOKEN</li>
</ul>
<a id="format_credentials" class="anchor" aria-label="Permalink: format_credentials" href="#format_credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">format_credentials</h2>
<pre><code>format_credentials(format-string)
</code></pre>
<p>Returns the credentials as a formatted string.  The &lt;format&gt; argument
allows you to include a format string that will be used to output each
of the credential parts.</p>
<pre><code>format("export %s=%s\n");
</code></pre>
<p>The default format is a "%s %s\n".</p>
<a id="find_credentials" class="anchor" aria-label="Permalink: find_credentials" href="#find_credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">find_credentials</h2>
<pre><code>find_credentials( option =&gt; value, ...);
</code></pre>
<p>You normally don't want to use this method. It's automatically invoked
by the constructor if you don't pass in any credentials. Accepts a
hash or hash reference consisting of keys (<code>order</code> or <code>profile</code>) in
the same manner as the constructor.</p>
<a id="get_creds_from_" class="anchor" aria-label="Permalink: get_creds_from_*" href="#get_creds_from_"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">get_creds_from_*</h2>
<p>These methods are called internally when the <code>new</code> constructor is
invoked. You should never need to call these methods. All of these
methods will return a hash of credential information and metadata
described below.</p>
<ul>
<li>
<p>aws_access_key_id</p>
<p>The AWS access key.</p>
</li>
<li>
<p>aws_secret_access_key</p>
<p>The AWS secret key.</p>
</li>
<li>
<p>token</p>
<p>Security token used with access keys.</p>
</li>
<li>
<p>expiration</p>
<p>Token expiration date.</p>
</li>
<li>
<p>role</p>
<p>IAM role if available.</p>
</li>
<li>
<p>source</p>
<p>The source from which the credentials were found.</p>
<ul>
<li>IAM - retrieved from container or instance role</li>
<li>container - <code>'ECS'</code> if retrieved via <code>AWS_CONTAINER_CREDENTIALS_RELATIVE_URI</code>;
<code>'full_uri'</code> if retrieved via <code>AWS_CONTAINER_CREDENTIALS_FULL_URI</code>
</li>
<li>web_identity - retrieved via STS AssumeRoleWithWebIdentity</li>
<li>file - retrieved from file</li>
<li>process - retrieved from an external process</li>
<li>ENV - retrieved from environment</li>
</ul>
</li>
</ul>
<a id="get_creds_from_container" class="anchor" aria-label="Permalink: get_creds_from_container" href="#get_creds_from_container"><span aria-hidden="true" class="octicon octicon-link"></span></a><h3 class="heading-element">get_creds_from_container</h3>
<pre><code>get_creds_from_container()
</code></pre>
<p>Retrieves credentials from the container credential endpoint. Supports
two mechanisms, tried in this order:</p>
<p><strong>Relative URI</strong> - if <code>AWS_CONTAINER_CREDENTIALS_RELATIVE_URI</code> is set,
credentials are fetched from:</p>
<pre><code>http://169.254.170.2/$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
</code></pre>
<p><strong>Full URI</strong> - if <code>AWS_CONTAINER_CREDENTIALS_FULL_URI</code> is set, that URL
is used directly. Covers Lambda execution roles, Fargate task roles, and
EKS Pod Identity. An authorization token is added automatically if
<code>AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE</code> or
<code>AWS_CONTAINER_AUTHORIZATION_TOKEN</code> is set in the environment.</p>
<p>Returns an empty hash if neither environment variable is set.</p>
<a id="get_creds_from_web_identity" class="anchor" aria-label="Permalink: get_creds_from_web_identity" href="#get_creds_from_web_identity"><span aria-hidden="true" class="octicon octicon-link"></span></a><h3 class="heading-element">get_creds_from_web_identity</h3>
<pre><code>get_creds_from_web_identity()
</code></pre>
<p>Retrieves temporary credentials by exchanging an OIDC/JWT web identity
token for AWS credentials via STS <code>AssumeRoleWithWebIdentity</code>. This is
the credential mechanism used by EKS IRSA (IAM Roles for Service
Accounts) and GitHub Actions OIDC federation.</p>
<p>Required environment variables:</p>
<ul>
<li>
<p><code>AWS_WEB_IDENTITY_TOKEN_FILE</code></p>
<p>Path to a file containing the OIDC/JWT token.</p>
</li>
<li>
<p><code>AWS_ROLE_ARN</code></p>
<p>ARN of the IAM role to assume.</p>
</li>
</ul>
<p>Optional:</p>
<ul>
<li>
<p><code>AWS_ROLE_SESSION_NAME</code></p>
<p>A name for the assumed role session. Defaults to
<code>amazon-credentials-session</code>.</p>
</li>
</ul>
<p>The STS call is made without AWS request signing - the OIDC token
itself authenticates the request, resolving the chicken-and-egg problem
of needing credentials to obtain credentials. The regional STS endpoint
is used when <code>AWS_DEFAULT_REGION</code> or <code>AWS_REGION</code> is set; otherwise
the global <code>sts.amazonaws.com</code> endpoint is used.</p>
<p>Returns an empty hash if the required environment variables are not set,
if the token file cannot be read, or if the STS call fails.</p>
<a id="get_creds_from_process" class="anchor" aria-label="Permalink: get_creds_from_process" href="#get_creds_from_process"><span aria-hidden="true" class="octicon octicon-link"></span></a><h3 class="heading-element">get_creds_from_process</h3>
<pre><code>get_creds_from_process(process)
</code></pre>
<p>Retrieves credentials from a helper process defined in the config
file. Returns the credentials tuple.</p>
<a id="get_creds_from_role" class="anchor" aria-label="Permalink: get_creds_from_role" href="#get_creds_from_role"><span aria-hidden="true" class="octicon octicon-link"></span></a><h3 class="heading-element">get_creds_from_role</h3>
<pre><code>get_creds_from_role()
</code></pre>
<p>Returns a hash, possibly containing access keys and a token.</p>
<a id="get_default_region" class="anchor" aria-label="Permalink: get_default_region" href="#get_default_region"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">get_default_region</h2>
<p>Returns the region of the currently running instance or container.
The constructor will set the region to this value unless you set your
own <code>region</code> value. Use <code>get_region</code> to retrieve the value after
instantiation or you can call this method again and it will make a
second call to retrieve the instance metadata.</p>
<a id="get_ec2_credentials-deprecated" class="anchor" aria-label="Permalink: get_ec2_credentials (deprecated)" href="#get_ec2_credentials-deprecated"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">get_ec2_credentials (deprecated)</h2>
<p>See <a href="#find_credentials">"find_credentials"</a></p>
<a id="is_token_expired" class="anchor" aria-label="Permalink: is_token_expired" href="#is_token_expired"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">is_token_expired</h2>
<pre><code>is_token_expired( window-interval )
</code></pre>
<p>Returns true if the token is about to expire (or is
expired). <code>window-interval</code> is the time in minutes before the actual
expiration time that the method should consider the token expired.
The default is 5 minutes.  Amazon states that new credentials will be
available <em>at least</em> 5 minutes before a token expires.</p>
<a id="normalize_arn" class="anchor" aria-label="Permalink: normalize_arn" href="#normalize_arn"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">normalize_arn</h2>
<pre><code>normalize_arn( arn )

# as an exported function
use Amazon::Credentials qw(normalize_arn);
my $iam_arn = normalize_arn($sts_arn);

# or as a method
my $iam_arn = $creds-&gt;normalize_arn($sts_arn);
</code></pre>
<p>Converts an STS assumed-role ARN to its equivalent IAM role ARN.</p>
<pre><code>arn:aws:sts::123456789:assumed-role/my-role/session-name
  =&gt; arn:aws:iam::123456789:role/my-role
</code></pre>
<p>This is useful when an ARN obtained from <code>GetCallerIdentity</code> needs to be
passed to IAM APIs such as <code>SimulatePrincipalPolicy</code> which require an IAM
ARN and will reject STS assumed-role ARNs. Non-assumed-role ARNs (IAM users,
IAM roles) are returned unchanged.</p>
<a id="reset_credentials" class="anchor" aria-label="Permalink: reset_credentials" href="#reset_credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">reset_credentials</h2>
<p>By default this method will remove credentials from the cache if you
pass a false or no value. Passing a true value will refresh your
credentials from the original source (equivalent to calling
<code>set_credentials</code>).</p>
<a id="refresh_token-deprecated" class="anchor" aria-label="Permalink: refresh_token (deprecated)" href="#refresh_token-deprecated"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">refresh_token (deprecated)</h2>
<p>use <code>refresh_credentials()</code></p>
<a id="refresh_credentials" class="anchor" aria-label="Permalink: refresh_credentials()" href="#refresh_credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">refresh_credentials()</h2>
<p>Retrieves a fresh set of IAM credentials.</p>
<pre><code>if ( $creds-&gt;is_token_expired ) {
  $creds-&gt;refresh_token()
}
</code></pre>
<a id="set_credentials" class="anchor" aria-label="Permalink: set_credentials" href="#set_credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">set_credentials</h2>
<p>Looks for your credentials according to the order specified by the
<code>order</code> attribute passed in the constructor and stores the
credentials in the cache.</p>
<p><em>Note that you should never have to call
this method. If you call this method it will ignore your cache
setting!</em></p>
<a id="sso-credentials" class="anchor" aria-label="Permalink: SSO CREDENTIALS" href="#sso-credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">SSO CREDENTIALS</h1>
<p>You can retrieve your SSO credentials after logging in using the
<code>sso_set_credentials</code> or <code>get_role_credentials</code> methods.</p>
<p>After logging in using your SSO credentials...</p>
<pre><code>aws sso login
</code></pre>
<p>...call one of the methods below to retrieve your credentials.</p>
<a id="get_role_credentials" class="anchor" aria-label="Permalink: get_role_credentials" href="#get_role_credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">get_role_credentials</h2>
<pre><code>get_role_credentials( options )
</code></pre>
<p><code>options</code> is a hash (not reference) of options</p>
<ul>
<li>
<p>role_name =&gt; role name (required)</p>
</li>
<li>
<p>account_id =&gt; AWS account id (required)</p>
</li>
<li>
<p>region =&gt; AWS region where SSO has been provisioned</p>
<p>default: $ENV{AWS_REGION}, $ENV{AWS_DEFAULT_REGION}, us-east-1</p>
</li>
</ul>
<a id="set_sso_credentials" class="anchor" aria-label="Permalink: set_sso_credentials" href="#set_sso_credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">set_sso_credentials</h2>
<pre><code>set_sso_options(role-name, account-id, region)
</code></pre>
<p>Calls <code>get_role_credentials</code> and set AWS credenital environment
variables. Region is optional, all other parameters are required.</p>
<pre><code>use Amazon::Credentials qw(set_sso_credentials)

set_sso_credentials(@ENV{qw(AWS_ROLE_NAME AWS_ACCOUNT_ID)});

my $credentials = Amazon::Credentials-&gt;new;
</code></pre>
<a id="settersgetters" class="anchor" aria-label="Permalink: SETTERS/GETTERS" href="#settersgetters"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">SETTERS/GETTERS</h1>
<p>All of the options described in the new method can be accessed by a
<em>getter</em> or set using a <em>setter</em> of the same name.</p>
<p>Example:</p>
<pre><code>$creds-&gt;set_cache(0);
</code></pre>
<a id="diagnostics" class="anchor" aria-label="Permalink: DIAGNOSTICS" href="#diagnostics"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">DIAGNOSTICS</h1>
<p>Set the <code>debug</code> option when you instantiate a <a href="https://metacpan.org/pod/Amazon%3A%3ACredentials" rel="nofollow">Amazon::Credentials</a>
object to output debug and diagnostic messages.</p>
<a id="configuration-and-environment" class="anchor" aria-label="Permalink: CONFIGURATION AND ENVIRONMENT" href="#configuration-and-environment"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">CONFIGURATION AND ENVIRONMENT</h1>
<p>The module will recognize several AWS specific environment variables
described throughout this documentation.</p>
<ul>
<li>AWS_ACCESS_KEY_ID</li>
<li>AWS_SECRET_ACCESS_KEY</li>
<li>AWS_SESSION_TOKEN</li>
<li>AWS_REGION</li>
<li>AWS_DEFAULT_REGION</li>
<li>AWS_CONTAINER_CREDENTIALS_RELATIVE_URI</li>
<li>AWS_CONTAINER_CREDENTIALS_FULL_URI</li>
<li>AWS_CONTAINER_AUTHORIZATION_TOKEN</li>
<li>AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE</li>
<li>AWS_WEB_IDENTITY_TOKEN_FILE</li>
<li>AWS_ROLE_ARN</li>
<li>AWS_ROLE_SESSION_NAME</li>
</ul>
<a id="bugs-and-limitations" class="anchor" aria-label="Permalink: BUGS AND LIMITATIONS" href="#bugs-and-limitations"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">BUGS AND LIMITATIONS</h1>
<p><a href="https://metacpan.org/pod/Amazon%3A%3ACredentials" rel="nofollow">Amazon::Credentials</a> will <strong>not</strong> attempt to retrieve temporary
credentials for profiles that specify a role. If for example you
define a role in your credentials file thusly:</p>
<pre><code>[developer]

 role_arn = arn:aws:iam::123456789012:role/developer-access-role
 source_profile = dev
</code></pre>
<p>The module will not return credentials for the <em>developer</em>
profile. While it would be theoretically possible to return those
credentials, in order to assume a role, one needs credentials (chicken
and egg problem).</p>
<p>Note that <code>get_creds_from_web_identity</code> resolves this problem for
OIDC-federated environments (EKS IRSA, GitHub Actions) by calling STS
<code>AssumeRoleWithWebIdentity</code>, which does not require AWS signing - the
OIDC token authenticates the request directly.</p>
<a id="dependencies" class="anchor" aria-label="Permalink: DEPENDENCIES" href="#dependencies"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">DEPENDENCIES</h1>
<p>Lower versions of these modules may be acceptable.</p>
<pre><code>'Class::Accessor::Fast' =&gt; '0.31'
'Config::Tiny'          =&gt; '2.28'
'File::HomeDir'         =&gt; '1.00'
'HTTP::Request'         =&gt; '6.00'
'HTTP::Tiny'            =&gt; '0.088'
'JSON::PP'              =&gt; '4.16'
'List::Util'            =&gt; '1.5'
'Net::SSLeay'           =&gt; '0'
'IO::Socket::SSL'       =&gt; '0'
'POSIX::strptime'       =&gt; '0.13'
</code></pre>
<p>...and possibly others</p>
<a id="security-considerations" class="anchor" aria-label="Permalink: SECURITY CONSIDERATIONS" href="#security-considerations"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">SECURITY CONSIDERATIONS</h1>
<p>The security concern around your credentials is not that they can be
retrieved and viewed - any process that compromises your environment
can use the same discovery methods this module does. If your
environment is compromised, an actor can resolve your credentials the
same way this module does. The real threat is <strong>exfiltration</strong>: your
credentials escaping your environment through logs, debug output,
serialized objects, or core dumps.</p>
<p><strong>Always take precautions to prevent accidental exfiltration of your
credentials.</strong></p>
<div class="markdown-heading"><h2 class="heading-element">How <code>Amazon::Credentials</code> Helps Prevent Exfiltration</h2><a id="how-amazoncredentials-helps-prevent-exfiltration" class="anchor" aria-label="Permalink: How Amazon::Credentials Helps Prevent Exfiltration" href="#how-amazoncredentials-helps-prevent-exfiltration"><span aria-hidden="true" class="octicon octicon-link"></span></a></div>
<a id="closure-based-credential-storage" class="anchor" aria-label="Permalink: Closure-Based Credential Storage" href="#closure-based-credential-storage"><span aria-hidden="true" class="octicon octicon-link"></span></a><h3 class="heading-element">Closure-Based Credential Storage</h3>
<p>Starting with version <em>1.3.0</em>, credentials are never stored as plain
scalar attributes on the object. Instead they are captured in Perl
closures. The object holds a code reference for each credential value;
calling it returns the credential. The values themselves live only in
the closure's lexical scope and are invisible to serialization:</p>
<pre><code>use Data::Dumper;
my $creds = Amazon::Credentials-&gt;new;
print Dumper $creds;
# _access_key_id     =&gt; sub { "DUMMY" },
# _secret_access_key =&gt; sub { "DUMMY" },
# _session_token     =&gt; sub { "DUMMY" },
</code></pre>
<p><code>Dumper</code>, <code>JSON::PP::encode_json</code>, exception stack traces, and
similar introspection tools will show only opaque code references -
never the credential values. This replaces the previous
encryption-based approach, which was both heavier (requiring
<a href="https://metacpan.org/pod/Crypt%3A%3ACBC" rel="nofollow">Crypt::CBC</a> and <a href="https://metacpan.org/pod/Crypt%3A%3ACipher%3A%3AAES" rel="nofollow">Crypt::Cipher::AES</a>) and weaker (the passkey lived
on the same object as the ciphertext unless you explictly sourced your
passkey from an external process).</p>
<a id="caching-and-memory" class="anchor" aria-label="Permalink: Caching and Memory" href="#caching-and-memory"><span aria-hidden="true" class="octicon octicon-link"></span></a><h3 class="heading-element">Caching and Memory</h3>
<p>Disabling the cache with <code>cache =&gt; 0</code> means credentials are
fetched on first use and the closures are reset to undef immediately
after each getter call. This limits the window during which a live
value exists in memory.</p>
<pre><code>my $credentials = Amazon::Credentials-&gt;new( cache =&gt; 0 );
</code></pre>
<p>However, <strong>Perl makes no guarantees about when or whether memory
containing a sensitive value is actually cleared</strong>. The interpreter
may retain a copy of the string in freed memory, in a copy-on-write
buffer, or in an arena waiting to be reclaimed. Disabling the cache
reduces the lifetime of credentials in the object, but it is not a
substitute for running in a properly secured environment.</p>
<p>If you need the credential tuple at once without it ever being split
across multiple getter calls, use <code>credential_keys()</code>:</p>
<pre><code>my $keys = $creds-&gt;credential_keys;
# { aws_access_key_id =&gt; ..., aws_secret_access_key =&gt; ..., token =&gt; ... }
</code></pre>
<ul>
<li>
<p>Option 2 - Remove them manually after use</p>
<p>Call <code>reset_credentials()</code> with a false value after fetching
credentials or after they are used by downstream processes. Call it
with a true value to regenerate them.</p>
</li>
<li>
<p>Using Multiple Instances of Amazon::Credentials</p>
<p>You may need to assume a role using initial credentials. In this case
you can use multiple instances of <a href="https://metacpan.org/pod/Amazon%3A%3ACredentials" rel="nofollow">Amazon::Credentials</a>.</p>
<pre><code>  # 1. retrieve SSO credentials
  my $sso_credentials = Amazon::Credentials-&gt;new(
    sso_role_name  =&gt; 'developer',
    sso_account_id =&gt; '01234567890'
  );

  # 2. assume a role in another account
  my $role_arn          = 'arn:aws:iam::09876543210:role/Route53AccountAccessRole';
  my $role_session_name = "route53-role-$PID";

  my $sts = Amazon::API::STS-&gt;new( credentials =&gt; $sso_credentials );

  my $assume_role_result = $sts-&gt;AssumeRole(
    { RoleArn         =&gt; $role_arn,
      RoleSessionName =&gt; $role_session_name,
    }
  );

  my $assumed = $assume_role_result-&gt;{AssumeRoleResult}{Credentials};

  # 3. create new credentials for assumed role
  my $role_credentials = Amazon::Credentials-&gt;new(
    aws_access_key_id     =&gt; $assumed-&gt;{AccessKeyId},
    aws_secret_access_key =&gt; $assumed-&gt;{SecretAccessKey},
    expiration            =&gt; $assumed-&gt;{Expiration},
    token                 =&gt; $assumed-&gt;{SessionToken},
  );

  # 4. make a call using the assumed role
  my $rt53 = Amazon::API::Route53-&gt;new( credentials =&gt; $role_credentials );

  my $response = $rt53-&gt;ListTagsForResources(
    { ResourceType =&gt; 'hostedzone',
      ResourceIds  =&gt; \@zone_ids,
    }
  );
</code></pre>
</li>
</ul>
<a id="securing-your-logs" class="anchor" aria-label="Permalink: Securing Your Logs" href="#securing-your-logs"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">Securing Your Logs</h2>
<p>To troubleshoot this module you can pass a <code>debug</code> flag that writes
diagnostic information to STDERR. Because credentials are stored as
closures, they cannot appear in debug output produced by
<a href="https://metacpan.org/pod/Data%3A%3ADumper" rel="nofollow">Data::Dumper</a> or similar tools - the object dump shows only code
references. You should still be careful with any application-level
logging that explicitly calls the getter methods and logs their return
values.</p>
<a id="use-temporary-credentials" class="anchor" aria-label="Permalink: Use Temporary Credentials" href="#use-temporary-credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">Use Temporary Credentials</h2>
<p>Use temporary credentials with short expiration times whenever
possible. <a href="https://metacpan.org/pod/Amazon%3A%3ACredentials" rel="nofollow">Amazon::Credentials</a> provides methods to check expiration
and refresh credentials when they have expired.</p>
<pre><code>if ( $credentials-&gt;is_token_expired ) {
  $credentials-&gt;refresh_token;
}
</code></pre>
<a id="use-granular-credentials" class="anchor" aria-label="Permalink: Use Granular Credentials" href="#use-granular-credentials"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">Use Granular Credentials</h2>
<p>Consider the APIs you are calling. If all you need is access to a
single S3 bucket, use credentials scoped to that bucket only. IAM
permissions can be quite specific about what resources credentials
can access and from where.</p>
<a id="notes-on-logging-and-debug-mode" class="anchor" aria-label="Permalink: Notes on Logging and Debug Mode" href="#notes-on-logging-and-debug-mode"><span aria-hidden="true" class="octicon octicon-link"></span></a><h2 class="heading-element">Notes on Logging and Debug Mode</h2>
<p>Starting with version <em>1.1.0</em>, <a href="https://metacpan.org/pod/Amazon%3A%3ACredentials" rel="nofollow">Amazon::Credentials</a> does <strong>not</strong>
use the <code>DEBUG</code> environment variable to enable debug output. You must
explicitly pass <code>debug =&gt; 1</code> to the constructor. This prevents
upstream modules that set <code>DEBUG</code> from inadvertently triggering debug
mode in <a href="https://metacpan.org/pod/Amazon%3A%3ACredentials" rel="nofollow">Amazon::Credentials</a>.</p>
<a id="incompatibilities" class="anchor" aria-label="Permalink: INCOMPATIBILITIES" href="#incompatibilities"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">INCOMPATIBILITIES</h1>
<p>This module has not been tested on Windows OS.</p>
<a id="contributing" class="anchor" aria-label="Permalink: CONTRIBUTING" href="#contributing"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">CONTRIBUTING</h1>
<p>You can find this project on GitHub at
<a href="https://github.com/rlauer6/perl-Amazon-Credentials">https://github.com/rlauer6/perl-Amazon-Credentials</a>.  PRs are always
welcomed!</p>
<a id="license-and-copyright" class="anchor" aria-label="Permalink: LICENSE AND COPYRIGHT" href="#license-and-copyright"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">LICENSE AND COPYRIGHT</h1>
<p>This module is free software. It may be used, redistributed and/or
modified under the same terms as Perl itself.</p>
<a id="author" class="anchor" aria-label="Permalink: AUTHOR" href="#author"><span aria-hidden="true" class="octicon octicon-link"></span></a><h1 class="heading-element">AUTHOR</h1>
<p>Rob Lauer - <a href="mailto:rlauer6@comcast.net">rlauer6@comcast.net</a></p>

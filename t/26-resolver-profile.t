#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use Amazon::Credentials::HTTP::Response;
use Amazon::Credentials::Resolver::Profile;
use Digest::SHA qw(sha1_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use Test::More;

{

  package TestUserAgent;

  use parent qw(Class::Accessor::Fast);

  __PACKAGE__->follow_best_practice;

  __PACKAGE__->mk_accessors(
    qw(
      requests
      responses
    )
  );

  sub new {
    my ( $class, @responses ) = @_;

    return bless {
      requests  => [],
      responses => \@responses,
    }, $class;
  }

  sub request {
    my ( $self, $request ) = @_;

    push @{ $self->get_requests }, $request;

    return shift @{ $self->get_responses };
  }
}

sub response {
  my ( $content, $status, $content_type ) = @_;

  $status       //= 200;
  $content_type //= q{};

  return Amazon::Credentials::HTTP::Response->new(
    { content => $content,
      headers => { 'content-type' => $content_type, },
      reason  => $status == 200 ? 'OK' : 'ERROR',
      status  => $status,
      success => $status == 200 ? 1 : 0,
    }
  );
}

sub write_json {
  my ( $path, $data ) = @_;

  return write_file( $path, encode_json($data) );
}

sub role_credentials_response {
  my ( $access_key, $secret_key, $token, $expiration ) = @_;

  $expiration //= 1_893_456_000_000;

  return encode_json(
    { roleCredentials => {
        accessKeyId     => $access_key,
        secretAccessKey => $secret_key,
        sessionToken    => $token,
        expiration      => $expiration,
      },
    }
  );
}

sub assume_role_response {
  my ( $access_key, $secret_key, $token ) = @_;

  return <<"XML";
<AssumeRoleResponse>
  <AssumeRoleResult>
    <Credentials>
      <AccessKeyId>$access_key</AccessKeyId>
      <SecretAccessKey>$secret_key</SecretAccessKey>
      <SessionToken>$token</SessionToken>
      <Expiration>2030-01-01T00:00:00Z</Expiration>
    </Credentials>
  </AssumeRoleResult>
</AssumeRoleResponse>
XML
}

sub create_home {
  my $home = tempdir( CLEANUP => 1 );

  make_path("$home/.aws");

  return $home;
}

sub write_file {
  my ( $path, $content ) = @_;

  open my $fh, '>', $path
    or die "cannot write $path: $!";

  print {$fh} $content;

  close $fh;

  return;
}

sub clear_environment {
  delete @ENV{
    qw(
      AWS_ACCESS_KEY_ID
      AWS_DEFAULT_REGION
      AWS_PROFILE
      AWS_REGION
      AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN
    )
  };

  return;
}

subtest 'missing profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile other]
region = us-east-1
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = $resolver->resolve('missing');

  ok( !defined $provider, 'missing profile returns undef' );

  return;
};

subtest 'static profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[static]
aws_access_key_id = static-access
aws_secret_access_key = static-secret
CREDS
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = $resolver->resolve('static');

  isa_ok( $provider, 'Amazon::Credentials::Provider::Config' );

  is( $provider->get_aws_access_key_id, 'static-access', 'static profile access key' );

  return;
};

subtest 'process profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  my $script = "$home/process.pl";

  write_file(
    $script,
    <<'SCRIPT'
#!/usr/bin/env perl

print <<'JSON';
{
  "Version": 1,
  "AccessKeyId": "process-access",
  "SecretAccessKey": "process-secret",
  "SessionToken": "process-token"
}
JSON
SCRIPT
  );

  chmod 0755, $script;

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile process]
credential_process = $script
region = us-east-1
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = $resolver->resolve('process');

  isa_ok( $provider, 'Amazon::Credentials::Provider::Process' );

  is( $provider->get_aws_access_key_id, 'process-access', 'process profile resolved' );

  return;
};

subtest 'role with static source profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[base]
aws_access_key_id = base-access
aws_secret_access_key = base-secret
CREDS
  );

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
source_profile = base
region = us-west-2
CONFIG
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::Config' );

  is( $provider->get_source_provider->get_aws_access_key_id, 'base-access', 'static source profile resolved' );

  is( $provider->get_region, 'us-west-2', 'role profile region propagated' );

  like( $ua->get_requests->[0]->header('Authorization'),
    qr/Credential=base-access\//, 'AssumeRole signed with source profile credentials' );

  return;
};

subtest 'role with MFA' => sub {
  local %ENV = %ENV;

  clear_environment();

  local $ENV{AMAZON_CREDENTIALS_MFA_TOKEN} = '123456';

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[base]
aws_access_key_id = base-access
aws_secret_access_key = base-secret
CREDS
  );

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
source_profile = base
mfa_serial = arn:aws:iam::123456789012:mfa/test
region = us-west-2
CONFIG
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  is( $provider->get_mfa_serial, 'arn:aws:iam::123456789012:mfa/test', 'MFA serial propagated' );

  like(
    $ua->get_requests->[0]->content,
    qr/(?:\A|&)SerialNumber=arn%3Aaws%3Aiam%3A%3A123456789012%3Amfa%2Ftest(?:&|\z)/,
    'MFA serial included in AssumeRole request'
  );

  like( $ua->get_requests->[0]->content, qr/(?:\A|&)TokenCode=123456(?:&|\z)/, 'MFA token included in AssumeRole request' );

  return;
};

subtest 'role with MFA requires token' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[base]
aws_access_key_id = base-access
aws_secret_access_key = base-secret
CREDS
  );

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
source_profile = base
mfa_serial = arn:aws:iam::123456789012:mfa/test
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('role'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/profile 'role' requires MFA but AMAZON_CREDENTIALS_MFA_TOKEN is not set/, 'missing MFA token croaks' );

  return;
};
subtest 'role with process source profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  my $script = "$home/process.pl";

  write_file(
    $script,
    <<'SCRIPT'
#!/usr/bin/env perl

print <<'JSON';
{
  "Version": 1,
  "AccessKeyId": "process-access",
  "SecretAccessKey": "process-secret",
  "SessionToken": "process-token"
}
JSON
SCRIPT
  );

  chmod 0755, $script;

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile base]
credential_process = $script
region = us-east-1

[profile role]
role_arn = arn:aws:iam::123456789012:role/test
source_profile = base
CONFIG
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::Process' );

  like(
    $ua->get_requests->[0]->header('Authorization'),
    qr/Credential=process-access\//,
    'AssumeRole signed with process credentials'
  );

  is( $ua->get_requests->[0]->header('x-amz-security-token'), 'process-token', 'process session token propagated' );

  return;
};

subtest 'two-level role chain' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[base]
aws_access_key_id = root-access
aws_secret_access_key = root-secret
CREDS
  );

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role-a]
role_arn = arn:aws:iam::123456789012:role/role-a
source_profile = base

[profile role-b]
role_arn = arn:aws:iam::123456789012:role/role-b
source_profile = role-a
CONFIG
  );

  my $ua = TestUserAgent->new(
    response( assume_role_response( 'role-a-access', 'role-a-secret', 'role-a-token' ) ),
    response( assume_role_response( 'role-b-access', 'role-b-secret', 'role-b-token' ) ),
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('role-b');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider->get_source_provider, 'Amazon::Credentials::Provider::Config' );

  is( scalar @{ $ua->get_requests }, 2, 'two STS calls made' );

  like( $ua->get_requests->[0]->header('Authorization'),
    qr/Credential=root-access\//, 'first role signed with root credentials' );

  like(
    $ua->get_requests->[1]->header('Authorization'),
    qr/Credential=role-a-access\//,
    'second role signed with first assumed role'
  );

  is( $provider->get_aws_access_key_id, 'role-b-access', 'outer role credentials returned' );

  return;
};

subtest 'three-level role chain' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[base]
aws_access_key_id = root-access
aws_secret_access_key = root-secret
CREDS
  );

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile a]
role_arn = arn:aws:iam::123456789012:role/a
source_profile = base

[profile b]
role_arn = arn:aws:iam::123456789012:role/b
source_profile = a

[profile c]
role_arn = arn:aws:iam::123456789012:role/c
source_profile = b
CONFIG
  );

  my $ua = TestUserAgent->new(
    response( assume_role_response( 'a-access', 'a-secret', 'a-token' ) ),
    response( assume_role_response( 'b-access', 'b-secret', 'b-token' ) ),
    response( assume_role_response( 'c-access', 'c-secret', 'c-token' ) ),
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('c');

  is( scalar @{ $ua->get_requests }, 3, 'three STS calls made' );

  is( $provider->get_aws_access_key_id, 'c-access', 'three-level role chain resolved' );

  return;
};

subtest 'role missing credential source' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('role'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/role_arn but no credential source/, 'missing credential source croaks' );

  return;
};

subtest 'missing source profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
source_profile = missing
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('role'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/unable to resolve source_profile 'missing'/, 'missing source profile croaks' );

  return;
};

subtest 'direct profile cycle' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile a]
role_arn = arn:aws:iam::123456789012:role/a
source_profile = a
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('a'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/credential profile cycle detected at 'a'/, 'direct cycle detected' );

  return;
};

subtest 'indirect profile cycle' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile a]
role_arn = arn:aws:iam::123456789012:role/a
source_profile = b

[profile b]
role_arn = arn:aws:iam::123456789012:role/b
source_profile = a
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('a'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/credential profile cycle detected at 'a'/, 'indirect cycle detected' );

  return;
};

subtest 'role parameters propagated' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[base]
aws_access_key_id = base-access
aws_secret_access_key = base-secret
CREDS
  );

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
source_profile = base
role_session_name = custom-session
external_id = external-123
duration_seconds = 7200
region = eu-west-1
CONFIG
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('role');

  is( $provider->get_role_session_name, 'custom-session', 'role session name propagated' );

  is( $provider->get_external_id, 'external-123', 'external id propagated' );

  is( $provider->get_duration_seconds, 7200, 'duration propagated' );

  is( $provider->get_region, 'eu-west-1', 'region propagated' );

  my $content = $ua->get_requests->[0]->content;

  like( $content, qr/(?:\A|&)RoleSessionName=custom-session(?:&|\z)/, 'session name sent to STS' );

  like( $content, qr/(?:\A|&)ExternalId=external-123(?:&|\z)/, 'external id sent to STS' );

  like( $content, qr/(?:\A|&)DurationSeconds=7200(?:&|\z)/, 'duration sent to STS' );

  return;
};

subtest 'credential_source Environment' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  $ENV{AWS_ACCESS_KEY_ID} = 'env-access';

  $ENV{AWS_SECRET_ACCESS_KEY} = 'env-secret';

  $ENV{AWS_SESSION_TOKEN} = 'env-token';

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = Environment
region = us-east-1
CONFIG
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::Env' );

  like( $ua->get_requests->[0]->header('Authorization'),
    qr/Credential=env-access\//, 'AssumeRole signed with environment credentials' );

  is( $ua->get_requests->[0]->header('x-amz-security-token'), 'env-token', 'environment session token propagated' );

  return;
};

subtest 'credential_source Ec2InstanceMetadata' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = Ec2InstanceMetadata
region = us-east-1
CONFIG
  );

  my $ua = TestUserAgent->new(
    response('test-imdsv2-token'),
    response("instance-role\n"),
    response(q|{"AccessKeyId":"imds-access","SecretAccessKey":"imds-secret","Token":"imds-token"}|),
    response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ),
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua, );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::InstanceRole' );

  is( $provider->get_source_provider->get_aws_access_key_id, 'imds-access', 'instance metadata credentials used as source' );

  like( $ua->get_requests->[3]->header('Authorization'),
    qr/Credential=imds-access\//, 'AssumeRole signed with instance role credentials' );

  is( $ua->get_requests->[3]->header('x-amz-security-token'), 'imds-token', 'instance role token propagated' );

  return;
};

########################################################################
subtest 'credential_source Ec2InstanceMetadata preferred falls back to IMDSv1' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = Ec2InstanceMetadata
region = us-east-1
CONFIG
  );

  my $ua = TestUserAgent->new(
    response( q{}, 500 ),
    response("instance-role\n"),
    response(q|{"AccessKeyId":"imds-access","SecretAccessKey":"imds-secret","Token":"imds-token"}|),
    response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ),
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new(
    imdsv2     => 'preferred',
    user_agent => $ua,
  );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::InstanceRole' );

  is( $provider->get_source_provider->get_aws_access_key_id,
    'imds-access', 'preferred mode falls back to IMDSv1 source credentials' );

  is( scalar @{ $ua->get_requests }, 4, 'token, role, credential, and AssumeRole requests made' );

  is( $ua->get_requests->[0]->method, 'PUT', 'IMDSv2 token request attempted first' );

  is( $ua->get_requests->[1]->method, 'GET', 'role request falls back to IMDSv1' );

  is( $ua->get_requests->[2]->method, 'GET', 'credential request uses IMDSv1' );

  ok( !$ua->get_requests->[1]->header('x-aws-ec2-metadata-token'), 'no token header on IMDSv1 role request' );

  ok( !$ua->get_requests->[2]->header('x-aws-ec2-metadata-token'), 'no token header on IMDSv1 credential request' );

  like( $ua->get_requests->[3]->header('Authorization'),
    qr/Credential=imds-access\//, 'AssumeRole signed with IMDSv1 source credentials' );

  is( $ua->get_requests->[3]->header('x-amz-security-token'), 'imds-token', 'IMDSv1 source session token propagated' );

  return;
};

subtest 'credential_source EcsContainer' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  $ENV{AWS_CONTAINER_CREDENTIALS_RELATIVE_URI} = '/v2/credentials/test';

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = EcsContainer
region = us-east-1
CONFIG
  );

  my $ua = TestUserAgent->new(
    response(q|{"AccessKeyId":"ecs-access","SecretAccessKey":"ecs-secret","Token":"ecs-token"}|),
    response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ),
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::Container' );

  is( $provider->get_source_provider->get_aws_access_key_id, 'ecs-access', 'container credentials used as source' );

  like( $ua->get_requests->[1]->header('Authorization'),
    qr/Credential=ecs-access\//, 'AssumeRole signed with container credentials' );

  is( $ua->get_requests->[1]->header('x-amz-security-token'), 'ecs-token', 'container session token propagated' );

  return;
};

subtest 'unsupported credential_source' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = SomethingElse
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('role'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/unsupported credential_source 'SomethingElse'/, 'unsupported credential source croaks' );

  return;
};

subtest 'source_profile and credential_source are mutually exclusive' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/credentials",
    <<'CREDS'
[base]
aws_access_key_id = base-access
aws_secret_access_key = base-secret
CREDS
  );

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
source_profile = base
credential_source = Environment
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('role'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/cannot specify both source_profile and credential_source/, 'mutually exclusive source options croak' );

  return;
};

subtest 'credential_source resolves to no provider' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = Environment
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('role'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/unable to resolve credential_source 'Environment'/, 'unavailable credential source croaks' );

  return;
};

subtest 'profile web identity' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  my $token_file = "$home/web-identity-token";

  write_file( $token_file, "profile-token\n" );

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile web]
role_arn = arn:aws:iam::123456789012:role/web
web_identity_token_file = $token_file
region = us-west-2
CONFIG
  );

  my $ua = TestUserAgent->new(
    response(
      <<'XML'
<AssumeRoleWithWebIdentityResponse>
  <AssumeRoleWithWebIdentityResult>
    <Credentials>
      <AccessKeyId>web-access</AccessKeyId>
      <SecretAccessKey>web-secret</SecretAccessKey>
      <SessionToken>web-token</SessionToken>
      <Expiration>2030-01-01T00:00:00Z</Expiration>
    </Credentials>
  </AssumeRoleWithWebIdentityResult>
</AssumeRoleWithWebIdentityResponse>
XML
    )
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('web');

  isa_ok( $provider, 'Amazon::Credentials::Provider::WebIdentity' );

  is( $provider->get_aws_access_key_id, 'web-access', 'web identity access key' );

  is( $provider->get_aws_secret_access_key, 'web-secret', 'web identity secret key' );

  is( $provider->get_token, 'web-token', 'web identity session token' );

  is( $provider->get_region, 'us-west-2', 'profile region propagated' );

  is( $provider->get_role_arn, 'arn:aws:iam::123456789012:role/web', 'role ARN propagated' );

  is( $provider->get_token_file, $token_file, 'token file propagated' );

  my $request = $ua->get_requests->[0];

  like( $request->uri->as_string, qr{\Ahttps://sts[.]us-west-2[.]amazonaws[.]com/}, 'regional STS endpoint' );

  like( $request->uri->as_string, qr/WebIdentityToken=profile-token/, 'token file content sent' );

  return;
};

subtest 'modern SSO profile resolves Provider::SSO' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  make_path("$home/.aws/sso/cache");

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sso]
region = us-east-2
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
sso_session = corporate

[sso-session corporate]
sso_region = us-west-2
sso_start_url = https://example.awsapps.com/start
CONFIG
  );

  my $cache_key = sha1_hex('corporate');

  write_json(
    "$home/.aws/sso/cache/$cache_key.json",
    { accessToken => 'access-token',
      expiresAt   => '2099-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new(
    response( role_credentials_response( 'sso-access', 'sso-secret', 'sso-token' ), 200, 'application/json' ) );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('sso');

  isa_ok( $provider, 'Amazon::Credentials::Provider::SSO' );

  is( $provider->get_aws_access_key_id, 'sso-access', 'SSO access key' );

  is( $provider->get_region, 'us-east-2', 'profile region retained' );

  is( $provider->get_sso_region, 'us-west-2', 'SSO portal region retained' );

  return;
};

########################################################################
subtest 'legacy SSO profile resolves Provider::SSO' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  make_path("$home/.aws/sso/cache");

  my $start_url = 'https://example.awsapps.com/start';

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile sso]
sso_account_id = 123456789012
sso_role_name = ReadOnlyAccess
sso_region = eu-west-1
sso_start_url = $start_url
CONFIG
  );

  my $cache_key = sha1_hex($start_url);

  write_json(
    "$home/.aws/sso/cache/$cache_key.json",
    { accessToken => 'legacy-token',
      expiresAt   => '2099-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new(
    response( role_credentials_response( 'legacy-access', 'legacy-secret', 'legacy-token' ), 200, 'application/json' ) );

  my $resolver = Amazon::Credentials::Resolver::Profile->new( user_agent => $ua );

  my $provider = $resolver->resolve('sso');

  isa_ok( $provider, 'Amazon::Credentials::Provider::SSO' );

  is( $provider->get_sso_region, 'eu-west-1', 'legacy SSO region' );

  return;
};

########################################################################
subtest 'incomplete SSO profile croaks' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sso]
sso_account_id = 123456789012
sso_region = us-east-1
sso_start_url = https://example.awsapps.com/start
CONFIG
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new;

  my $provider = eval { return $resolver->resolve('sso'); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/incomplete SSO configuration/, 'incomplete SSO profile croaks' );

  return;
};

########################################################################
subtest 'credential_source Ec2InstanceMetadata required failure' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = Ec2InstanceMetadata
region = us-east-1
CONFIG
  );

  my $ua = TestUserAgent->new( response( q{}, 500 ), );

  my $resolver = Amazon::Credentials::Resolver::Profile->new(
    imdsv2     => 'required',
    user_agent => $ua,
  );

  my $provider = eval { return $resolver->resolve('role'); };

  ok( !defined $provider, 'provider not returned', );

  like( $@, qr/could not retrieve IMDSv2 token/, 'required IMDSv2 failure propagates', );

  is( scalar @{ $ua->get_requests }, 1, 'only token request attempted', );

  is( $ua->get_requests->[0]->method, 'PUT', 'IMDSv2 token request attempted', );

  return;
};

########################################################################
subtest 'credential_source Ec2InstanceMetadata disabled' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $home = create_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile role]
role_arn = arn:aws:iam::123456789012:role/test
credential_source = Ec2InstanceMetadata
region = us-east-1
CONFIG
  );

  my $ua = TestUserAgent->new(
    response("instance-role\n"),
    response(q|{"AccessKeyId":"imds-access","SecretAccessKey":"imds-secret","Token":"imds-token"}|),
    response( assume_role_response( 'role-access', 'role-secret', 'role-token', ), ),
  );

  my $resolver = Amazon::Credentials::Resolver::Profile->new(
    imdsv2     => 'disabled',
    user_agent => $ua,
  );

  my $provider = $resolver->resolve('role');

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole', );

  isa_ok( $provider->get_source_provider, 'Amazon::Credentials::Provider::InstanceRole', );

  is( scalar @{ $ua->get_requests }, 3, 'role discovery, credentials, and AssumeRole requests made', );

  is( $ua->get_requests->[0]->method, 'GET', 'disabled mode skips IMDSv2 token request', );

  is( $provider->get_source_provider->get_aws_access_key_id, 'imds-access', 'IMDSv1 credentials used as source', );

  return;
};

done_testing;

1;

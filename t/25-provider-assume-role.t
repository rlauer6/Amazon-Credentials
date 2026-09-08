#!/usr/bin/env perl;

use strict;
use warnings;

use 5.010;

use Amazon::Credentials::HTTP::Response;
use Amazon::Credentials::Provider;
use Amazon::Credentials::Provider::AssumeRole;
use Test::More;

{

  package TestProvider;

  use parent qw(Amazon::Credentials::Provider);

  __PACKAGE__->follow_best_practice;

  __PACKAGE__->mk_accessors(
    qw(
      refresh_count
      refreshable
    )
  );

  sub new {
    my ( $class, %args ) = @_;

    my $self = $class->SUPER::new(
      aws_access_key_id     => $args{aws_access_key_id},
      aws_secret_access_key => $args{aws_secret_access_key},
      region                => $args{region},
      source                => 'test',
      token                 => $args{token},
    );

    $self->set_refresh_count(0);
    $self->set_refreshable( $args{refreshable} // 0 );

    return $self;
  }

  sub is_refreshable {
    my ($self) = @_;

    return $self->get_refreshable;
  }

  sub refresh_credentials {
    my ($self) = @_;

    $self->set_refresh_count( $self->get_refresh_count + 1 );

    $self->set_aws_access_key_id('refreshed-access');

    $self->set_aws_secret_access_key('refreshed-secret');

    $self->set_token('refreshed-token');

    return $self;
  }
}

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
  my ( $content, $status ) = @_;

  $status //= 200;

  return Amazon::Credentials::HTTP::Response->new(
    { content => $content,
      headers => {},
      reason  => $status == 200 ? 'OK' : 'ERROR',
      status  => $status,
      success => $status == 200 ? 1 : 0,
    }
  );
}

sub assume_role_response {
  my ( $access_key, $secret_key, $token, $expiration ) = @_;

  $expiration //= '2030-01-01T00:00:00Z';

  return <<"XML";
<AssumeRoleResponse>
  <AssumeRoleResult>
    <Credentials>
      <AccessKeyId>$access_key</AccessKeyId>
      <SecretAccessKey>$secret_key</SecretAccessKey>
      <SessionToken>$token</SessionToken>
      <Expiration>$expiration</Expiration>
    </Credentials>
  </AssumeRoleResult>
</AssumeRoleResponse>
XML
}

subtest 'provider not applicable' => sub {
  my $provider = Amazon::Credentials::Provider::AssumeRole->new;

  ok( !defined $provider, 'returns undef without role ARN' );

  return;
};

subtest 'role ARN requires source provider' => sub {
  my $provider
    = eval { return Amazon::Credentials::Provider::AssumeRole->new( role_arn => 'arn:aws:iam::123456789012:role/test' ); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/source_provider is required/, 'missing source provider croaks' );

  return;
};

subtest 'assume role credentials' => sub {
  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-west-2',
    token                 => 'source-token',
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $provider = Amazon::Credentials::Provider::AssumeRole->new(
    role_arn        => 'arn:aws:iam::123456789012:role/test',
    source_provider => $source,
    user_agent      => $ua,
  );

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  is( $provider->get_source, 'assume_role', 'provider source' );

  is( $provider->get_aws_access_key_id, 'role-access', 'assumed access key' );

  is( $provider->get_aws_secret_access_key, 'role-secret', 'assumed secret key' );

  is( $provider->get_token, 'role-token', 'assumed session token' );

  is( $provider->get_expiration, '2030-01-01T00:00:00Z', 'expiration' );

  is( $provider->get_region, 'us-west-2', 'region inherited from source provider' );

  is( $provider->get_source_provider, $source, 'source provider retained' );

  ok( $provider->is_refreshable, 'AssumeRole provider is refreshable' );

  is( scalar @{ $ua->get_requests }, 1, 'one STS request' );

  my $request = $ua->get_requests->[0];

  is( $request->method, 'POST', 'AssumeRole uses POST' );

  is( $request->uri->as_string, 'https://sts.us-west-2.amazonaws.com/', 'regional STS endpoint' );

  like( $request->content, qr/(?:\A|&)Action=AssumeRole(?:&|\z)/, 'AssumeRole action' );

  like( $request->content, qr/(?:\A|&)RoleArn=arn%3Aaws%3Aiam%3A%3A123456789012%3Arole%2Ftest(?:&|\z)/, 'role ARN encoded' );

  like( $request->content, qr/(?:\A|&)RoleSessionName=amazon-credentials-session(?:&|\z)/, 'default role session name' );

  like( $request->header('Authorization'), qr/\AAWS4-HMAC-SHA256 /, 'request signed' );

  like( $request->header('Authorization'), qr/Credential=source-access\//, 'source access key used for signing' );

  is( $request->header('x-amz-security-token'), 'source-token', 'source session token used for signing' );

  return;
};

subtest 'explicit role parameters' => sub {
  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-east-1',
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $provider = Amazon::Credentials::Provider::AssumeRole->new(
    duration_seconds  => 3600,
    external_id       => 'external-123',
    role_arn          => 'arn:aws:iam::123456789012:role/test',
    role_session_name => 'my-session',
    source_provider   => $source,
    user_agent        => $ua,
  );

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  is( $provider->get_duration_seconds, 3600, 'duration retained' );

  is( $provider->get_external_id, 'external-123', 'external id retained' );

  is( $provider->get_role_session_name, 'my-session', 'role session name retained' );

  my $content = $ua->get_requests->[0]->content;

  like( $content, qr/(?:\A|&)DurationSeconds=3600(?:&|\z)/, 'duration sent' );

  like( $content, qr/(?:\A|&)ExternalId=external-123(?:&|\z)/, 'external id sent' );

  like( $content, qr/(?:\A|&)RoleSessionName=my-session(?:&|\z)/, 'explicit session name sent' );

  return;
};

########################################################################
subtest 'MFA parameters' => sub {
########################################################################
  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-east-1',
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access', 'role-secret', 'role-token' ) ) );

  my $provider = Amazon::Credentials::Provider::AssumeRole->new(
    mfa_serial      => 'arn:aws:iam::123456789012:mfa/test',
    mfa_token       => '123456',
    role_arn        => 'arn:aws:iam::123456789012:role/test',
    source_provider => $source,
    user_agent      => $ua,
  );

  isa_ok( $provider, 'Amazon::Credentials::Provider::AssumeRole' );

  is( $provider->get_mfa_serial, 'arn:aws:iam::123456789012:mfa/test', 'MFA serial retained' );

  my $content = $ua->get_requests->[0]->content;

  like( $content, qr/(?:\A|&)SerialNumber=arn%3Aaws%3Aiam%3A%3A123456789012%3Amfa%2Ftest(?:&|\z)/, 'MFA serial sent' );

  like( $content, qr/(?:\A|&)TokenCode=123456(?:&|\z)/, 'MFA token sent' );

  return;
};

########################################################################
subtest 'STS failure' => sub {
########################################################################
  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-east-1',
  );

  my $ua = TestUserAgent->new(
    response(
      <<'XML',
<ErrorResponse>
  <Error>
    <Code>AccessDenied</Code>
    <Message>not authorized</Message>
  </Error>
</ErrorResponse>
XML
      403
    )
  );

  my $provider = eval {
    return Amazon::Credentials::Provider::AssumeRole->new(
      role_arn        => 'arn:aws:iam::123456789012:role/test',
      source_provider => $source,
      user_agent      => $ua,
    );
  };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/AccessDenied/, 'STS error code included' );

  like( $@, qr/not authorized/, 'STS error message included' );

  return;
};

subtest 'refresh with non-refreshable source' => sub {
  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-east-1',
    refreshable           => 0,
  );

  my $ua = TestUserAgent->new(
    response( assume_role_response( 'role-access-1', 'role-secret-1', 'role-token-1' ) ),
    response( assume_role_response( 'role-access-2', 'role-secret-2', 'role-token-2' ) ),
  );

  my $provider = Amazon::Credentials::Provider::AssumeRole->new(
    role_arn        => 'arn:aws:iam::123456789012:role/test',
    source_provider => $source,
    user_agent      => $ua,
  );

  my $before = time;

  my $result = $provider->refresh_credentials;

  my $after = time;

  is( $result, $provider, 'refresh returns provider' );

  is( $source->get_refresh_count, 0, 'non-refreshable source not refreshed' );

  is( $provider->get_aws_access_key_id, 'role-access-2', 'assumed credentials refreshed' );

  is( $provider->get_aws_secret_access_key, 'role-secret-2', 'secret refreshed' );

  is( $provider->get_token, 'role-token-2', 'token refreshed' );

  cmp_ok( $provider->get_last_refreshed, '>=', $before, 'last_refreshed lower bound' );

  cmp_ok( $provider->get_last_refreshed, '<=', $after, 'last_refreshed upper bound' );

  return;
};

subtest 'refreshable source refreshed first' => sub {
  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-east-1',
    refreshable           => 1,
    token                 => 'source-token',
  );

  my $ua = TestUserAgent->new(
    response( assume_role_response( 'role-access-1', 'role-secret-1', 'role-token-1' ) ),
    response( assume_role_response( 'role-access-2', 'role-secret-2', 'role-token-2' ) ),
  );

  my $provider = Amazon::Credentials::Provider::AssumeRole->new(
    role_arn        => 'arn:aws:iam::123456789012:role/test',
    source_provider => $source,
    user_agent      => $ua,
  );

  $provider->refresh_credentials;

  is( $source->get_refresh_count, 1, 'source provider refreshed' );

  my $request = $ua->get_requests->[1];

  like( $request->header('Authorization'), qr/Credential=refreshed-access\//, 'refreshed source access key used' );

  is( $request->header('x-amz-security-token'), 'refreshed-token', 'refreshed source token used' );

  return;
};

subtest 'MFA refresh uses fresh token' => sub {
  local $ENV{AMAZON_CREDENTIALS_MFA_TOKEN} = '111111';

  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-east-1',
  );

  my $ua = TestUserAgent->new(
    response( assume_role_response( 'role-access-1', 'role-secret-1', 'role-token-1' ) ),
    response( assume_role_response( 'role-access-2', 'role-secret-2', 'role-token-2' ) )
  );

  my $provider = Amazon::Credentials::Provider::AssumeRole->new(
    mfa_serial      => 'arn:aws:iam::123456789012:mfa/test',
    mfa_token       => $ENV{AMAZON_CREDENTIALS_MFA_TOKEN},
    role_arn        => 'arn:aws:iam::123456789012:role/test',
    source_provider => $source,
    user_agent      => $ua,
  );

  $ENV{AMAZON_CREDENTIALS_MFA_TOKEN} = '222222';

  $provider->refresh_credentials;

  is( scalar @{ $ua->get_requests }, 2, 'initial and refresh AssumeRole requests made' );

  like( $ua->get_requests->[0]->content, qr/(?:\A|&)TokenCode=111111(?:&|\z)/, 'initial AssumeRole uses initial MFA token' );

  like( $ua->get_requests->[1]->content, qr/(?:\A|&)TokenCode=222222(?:&|\z)/, 'refresh uses fresh MFA token' );

  return;
};

subtest 'nested AssumeRole providers' => sub {
  my $source = TestProvider->new(
    aws_access_key_id     => 'root-access',
    aws_secret_access_key => 'root-secret',
    region                => 'us-east-1',
    refreshable           => 0,
  );

  my $ua_a = TestUserAgent->new(
    response( assume_role_response( 'role-a-access',         'role-a-secret',         'role-a-token' ) ),
    response( assume_role_response( 'role-a-refresh-access', 'role-a-refresh-secret', 'role-a-refresh-token' ) ),
  );

  my $role_a = Amazon::Credentials::Provider::AssumeRole->new(
    role_arn          => 'arn:aws:iam::123456789012:role/role-a',
    role_session_name => 'role-a-session',
    source_provider   => $source,
    user_agent        => $ua_a,
  );

  my $ua_b = TestUserAgent->new(
    response( assume_role_response( 'role-b-access',         'role-b-secret',         'role-b-token' ) ),
    response( assume_role_response( 'role-b-refresh-access', 'role-b-refresh-secret', 'role-b-refresh-token' ) ),
  );

  my $role_b = Amazon::Credentials::Provider::AssumeRole->new(
    role_arn          => 'arn:aws:iam::123456789012:role/role-b',
    role_session_name => 'role-b-session',
    source_provider   => $role_a,
    user_agent        => $ua_b,
  );

  is( $role_b->get_source_provider, $role_a, 'nested source provider retained' );

  like(
    $ua_b->get_requests->[0]->header('Authorization'),
    qr/Credential=role-a-access\//,
    'outer role initially signed with inner role'
  );

  is( $ua_b->get_requests->[0]->header('x-amz-security-token'), 'role-a-token', 'inner role token used initially' );

  $role_b->refresh_credentials;

  is( $role_a->get_aws_access_key_id, 'role-a-refresh-access', 'inner role refreshed' );

  is( $role_b->get_aws_access_key_id, 'role-b-refresh-access', 'outer role refreshed' );

  like(
    $ua_b->get_requests->[1]->header('Authorization'),
    qr/Credential=role-a-refresh-access\//,
    'outer refresh signed with refreshed inner role'
  );

  is( $ua_b->get_requests->[1]->header('x-amz-security-token'),
    'role-a-refresh-token', 'outer refresh uses refreshed inner token' );

  return;
};

subtest 'MFA refresh requires fresh token' => sub {
  local $ENV{AMAZON_CREDENTIALS_MFA_TOKEN} = '111111';

  my $source = TestProvider->new(
    aws_access_key_id     => 'source-access',
    aws_secret_access_key => 'source-secret',
    region                => 'us-east-1',
  );

  my $ua = TestUserAgent->new( response( assume_role_response( 'role-access-1', 'role-secret-1', 'role-token-1' ) ) );

  my $provider = Amazon::Credentials::Provider::AssumeRole->new(
    mfa_serial      => 'arn:aws:iam::123456789012:mfa/test',
    mfa_token       => $ENV{AMAZON_CREDENTIALS_MFA_TOKEN},
    role_arn        => 'arn:aws:iam::123456789012:role/test',
    source_provider => $source,
    user_agent      => $ua,
  );

  delete $ENV{AMAZON_CREDENTIALS_MFA_TOKEN};

  my $result = eval {
    $provider->refresh_credentials;
    return 1;
  };

  ok( !$result, 'refresh fails without fresh MFA token' );

  like( $@, qr/MFA refresh requires AMAZON_CREDENTIALS_MFA_TOKEN/, 'refresh reports missing MFA token' );

  is( scalar @{ $ua->get_requests }, 1, 'no second AssumeRole request made' );

  return;
};

done_testing;

1;

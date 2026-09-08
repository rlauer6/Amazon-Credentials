#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use Amazon::Credentials::HTTP::Response;
use Amazon::Credentials::Provider::SSO;
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
  my ( $content, $status ) = @_;

  $status //= 200;

  return Amazon::Credentials::HTTP::Response->new(
    { content => $content,
      headers => { 'content-type' => 'application/json', },
      reason  => $status == 200 ? 'OK' : 'ERROR',
      status  => $status,
      success => $status == 200 ? 1 : 0,
    }
  );
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

sub write_file {
  my ( $path, $content ) = @_;

  open my $fh, '>', $path
    or die "cannot write $path: $!";

  print {$fh} $content;

  close $fh;

  return;
}

sub write_json {
  my ( $path, $data ) = @_;

  return write_file( $path, encode_json($data) );
}

sub create_aws_home {
  my $home = tempdir( CLEANUP => 1 );

  make_path("$home/.aws/sso/cache");

  return $home;
}

sub clear_environment {
  delete @ENV{
    qw(
      AWS_DEFAULT_REGION
      AWS_PROFILE
      AWS_REGION
    )
  };

  return;
}

subtest 'non-SSO profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile static]
region = us-east-1
aws_access_key_id = access
aws_secret_access_key = secret
CONFIG
  );

  my $provider = Amazon::Credentials::Provider::SSO->new( profile => 'static' );

  ok( !defined $provider, 'non-SSO profile returns undef' );

  return;
};

subtest 'incomplete SSO profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile test]
sso_account_id = 123456789012
sso_start_url = https://example.awsapps.com/start
sso_region = us-west-2
CONFIG
  );

  my $provider = eval { return Amazon::Credentials::Provider::SSO->new( profile => 'test' ); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/incomplete SSO configuration/, 'incomplete SSO profile croaks' );

  return;
};

subtest 'missing SSO session' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile test]
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
sso_session = missing
CONFIG
  );

  my $provider = eval { return Amazon::Credentials::Provider::SSO->new( profile => 'test' ); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/no \[sso-session missing\]/, 'missing SSO session croaks' );

  return;
};

subtest 'modern SSO session profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile test]
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

  my $ua = TestUserAgent->new( response( role_credentials_response( 'access', 'secret', 'session-token' ) ) );

  my $provider = Amazon::Credentials::Provider::SSO->new(
    profile    => 'test',
    user_agent => $ua,
  );

  isa_ok( $provider, 'Amazon::Credentials::Provider::SSO' );

  is( $provider->get_source, 'sso', 'provider source' );

  is( $provider->get_profile, 'test', 'profile retained' );

  is( $provider->get_account_id, '123456789012', 'account id retained' );

  is( $provider->get_role_name, 'AdministratorAccess', 'role name retained' );

  is( $provider->get_session_name, 'corporate', 'session name retained' );

  is( $provider->get_sso_region, 'us-west-2', 'SSO region retained' );

  is( $provider->get_region, 'us-east-2', 'profile region retained for credentials' );

  is( $provider->get_sso_start_url, 'https://example.awsapps.com/start', 'SSO start URL retained' );

  is( $provider->get_cache_key, $cache_key, 'session-name cache key retained' );

  is( $provider->get_aws_access_key_id, 'access', 'access key' );

  is( $provider->get_aws_secret_access_key, 'secret', 'secret key' );

  is( $provider->get_token, 'session-token', 'session token' );

  ok( $provider->is_refreshable, 'SSO provider is refreshable' );

  is( scalar @{ $ua->get_requests }, 1, 'one GetRoleCredentials request' );

  my $request = $ua->get_requests->[0];

  is( $request->method, 'GET', 'GetRoleCredentials uses GET' );

  is(
    $request->uri->as_string,
    'https://portal.sso.us-west-2.amazonaws.com/federation/credentials?account_id=123456789012&role_name=AdministratorAccess',
    'regional SSO portal endpoint'
  );

  is( $request->header(':x-amz-sso_bearer_token'), 'access-token', 'bearer token header' );

  return;
};

subtest 'legacy inline SSO profile' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  my $start_url = 'https://example.awsapps.com/start';

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile test]
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

  my $ua = TestUserAgent->new( response( role_credentials_response( 'access', 'secret', 'token' ) ) );

  my $provider = Amazon::Credentials::Provider::SSO->new(
    profile    => 'test',
    user_agent => $ua,
  );

  isa_ok( $provider, 'Amazon::Credentials::Provider::SSO' );

  ok( !defined $provider->get_session_name, 'legacy profile has no session name' );

  is( $provider->get_cache_key, $cache_key, 'legacy cache key uses start URL' );

  is( $provider->get_sso_region, 'eu-west-1', 'legacy SSO region' );

  is( $provider->get_region, 'eu-west-1', 'SSO region used as credential region' );

  return;
};

subtest 'expiration normalized' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  my $start_url = 'https://example.awsapps.com/start';

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile test]
sso_account_id = 123456789012
sso_role_name = ReadOnlyAccess
sso_region = us-east-1
sso_start_url = $start_url
CONFIG
  );

  my $cache_key = sha1_hex($start_url);

  write_json(
    "$home/.aws/sso/cache/$cache_key.json",
    { accessToken => 'access-token',
      expiresAt   => '2099-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new( response( role_credentials_response( 'access', 'secret', 'token', 1_893_456_000_000 ) ) );

  my $provider = Amazon::Credentials::Provider::SSO->new(
    profile    => 'test',
    user_agent => $ua,
  );

  like( $provider->get_expiration, qr/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, 'epoch milliseconds normalized to ISO-8601' );

  return;
};

subtest 'GetRoleCredentials failure' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  my $start_url = 'https://example.awsapps.com/start';

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile test]
sso_account_id = 123456789012
sso_role_name = ReadOnlyAccess
sso_region = us-east-1
sso_start_url = $start_url
CONFIG
  );

  my $cache_key = sha1_hex($start_url);

  write_json(
    "$home/.aws/sso/cache/$cache_key.json",
    { accessToken => 'access-token',
      expiresAt   => '2099-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new( response( encode_json( { message => 'role not found', } ), 404 ) );

  my $provider = eval { return Amazon::Credentials::Provider::SSO->new( profile => 'test', user_agent => $ua, ); };

  ok( !defined $provider, 'provider not returned' );

  like( $@, qr/role not found/, 'GetRoleCredentials failure croaks' );

  return;
};

subtest 'public get_role_credentials' => sub {

  no warnings 'redefine';

  local *Amazon::Credentials::Provider::SSO::_get_access_token = sub {
    return 'cached-token';
  };

  local *Amazon::Credentials::Provider::SSO::_get_role_credentials = sub {
    my ( $class, @args ) = @_;

    my $options
      = ref $args[0]
      ? $args[0]
      : {@args};

    is( $options->{account_id}, '123456789012', 'account id propagated', );

    is( $options->{role_name}, 'AWSAdministratorAccess', 'role name propagated', );

    is( $options->{access_token}, 'cached-token', 'cached access token used', );

    return {
      accessKeyId     => 'access',
      secretAccessKey => 'secret',
      sessionToken    => 'token',
    };
  };

  my $credentials = Amazon::Credentials::Provider::SSO->get_role_credentials(
    { account_id => '123456789012',
      role_name  => 'AWSAdministratorAccess',
      region     => 'us-east-1',
    }
  );

  is( $credentials->{accessKeyId}, 'access', 'role credentials returned', );

  return;
};

subtest 'refresh role credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  my $start_url = 'https://example.awsapps.com/start';

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile test]
sso_account_id = 123456789012
sso_role_name = ReadOnlyAccess
sso_region = us-east-1
sso_start_url = $start_url
CONFIG
  );

  my $cache_key = sha1_hex($start_url);

  write_json(
    "$home/.aws/sso/cache/$cache_key.json",
    { accessToken => 'access-token',
      expiresAt   => '2099-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new(
    response( role_credentials_response( 'access-1', 'secret-1', 'token-1' ) ),
    response( role_credentials_response( 'access-2', 'secret-2', 'token-2' ) ),
  );

  my $provider = Amazon::Credentials::Provider::SSO->new(
    profile    => 'test',
    user_agent => $ua,
  );

  my $before = time;

  my $result = $provider->refresh_credentials;

  my $after = time;

  is( $result, $provider, 'refresh returns provider' );

  is( $provider->get_aws_access_key_id, 'access-2', 'refreshed access key' );

  is( $provider->get_aws_secret_access_key, 'secret-2', 'refreshed secret key' );

  is( $provider->get_token, 'token-2', 'refreshed session token' );

  cmp_ok( $provider->get_last_refreshed, '>=', $before, 'last_refreshed lower bound' );

  cmp_ok( $provider->get_last_refreshed, '<=', $after, 'last_refreshed upper bound' );

  is( scalar @{ $ua->get_requests }, 2, 'refresh performs another GetRoleCredentials request' );

  return;
};

subtest 'refresh expired SSO access token first' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = create_aws_home();

  local $ENV{HOME} = $home;

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile test]
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
sso_session = corporate

[sso-session corporate]
sso_region = us-west-2
sso_start_url = https://example.awsapps.com/start
CONFIG
  );

  my $cache_key  = sha1_hex('corporate');
  my $cache_file = "$home/.aws/sso/cache/$cache_key.json";

  write_json(
    $cache_file,
    { accessToken           => 'initial-token',
      clientId              => 'client-id',
      clientSecret          => 'client-secret',
      expiresAt             => '2099-01-01T00:00:00Z',
      refreshToken          => 'refresh-token',
      registrationExpiresAt => '2099-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new(
    response( role_credentials_response( 'access-1', 'secret-1', 'session-1' ) ),
    response(
      encode_json(
        { accessToken => 'refreshed-access-token',
          expiresIn   => 3600,
        }
      )
    ),
    response( role_credentials_response( 'access-2', 'secret-2', 'session-2' ) ),
  );

  my $provider = Amazon::Credentials::Provider::SSO->new(
    profile    => 'test',
    user_agent => $ua,
  );

  write_json(
    $cache_file,
    { accessToken           => 'expired-token',
      clientId              => 'client-id',
      clientSecret          => 'client-secret',
      expiresAt             => '2020-01-01T00:00:00Z',
      refreshToken          => 'refresh-token',
      registrationExpiresAt => '2099-01-01T00:00:00Z',
    }
  );

  $provider->refresh_credentials;

  is( scalar @{ $ua->get_requests }, 3, 'refresh performs OIDC refresh and GetRoleCredentials' );

  is( $ua->get_requests->[1]->method, 'POST', 'expired SSO token refresh uses POST' );

  is(
    $ua->get_requests->[1]->uri->as_string,
    'https://oidc.us-west-2.amazonaws.com/token',
    'SSO token refreshed through regional OIDC endpoint'
  );

  is( $ua->get_requests->[2]->header(':x-amz-sso_bearer_token'),
    'refreshed-access-token', 'new access token used for role credentials' );

  is( $provider->get_aws_access_key_id, 'access-2', 'role credentials refreshed after access token' );

  return;
};

done_testing;

1;

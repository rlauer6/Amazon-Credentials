#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use Amazon::Credentials::HTTP::Response;
use Amazon::Credentials::Provider::WebIdentity;
use File::Temp qw(tempdir);
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
      headers => {},
      reason  => $status == 200 ? 'OK' : 'ERROR',
      status  => $status,
      success => $status == 200 ? 1 : 0,
    }
  );
}

sub credentials_response {
  my ( $access_key, $secret_key, $token ) = @_;

  return <<"XML";
<AssumeRoleWithWebIdentityResponse>
  <AssumeRoleWithWebIdentityResult>
    <Credentials>
      <AccessKeyId>$access_key</AccessKeyId>
      <SecretAccessKey>$secret_key</SecretAccessKey>
      <SessionToken>$token</SessionToken>
      <Expiration>2030-01-01T00:00:00Z</Expiration>
    </Credentials>
  </AssumeRoleWithWebIdentityResult>
</AssumeRoleWithWebIdentityResponse>
XML
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
      AWS_DEFAULT_REGION
      AWS_REGION
      AWS_ROLE_ARN
      AWS_ROLE_SESSION_NAME
      AWS_WEB_IDENTITY_TOKEN_FILE
    )
  };

  return;
}

subtest 'provider not applicable' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $provider = Amazon::Credentials::Provider::WebIdentity->new;

  ok !defined $provider, 'returns undef when web identity environment is absent';

  return;
};

subtest 'incomplete environment' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_ROLE_ARN} = 'arn:aws:iam::123456789012:role/test';

  my $provider = eval { return Amazon::Credentials::Provider::WebIdentity->new; };

  ok !defined $provider, 'provider not returned';

  like $@, qr/AWS_WEB_IDENTITY_TOKEN_FILE/, 'missing token file croaks';

  clear_environment();

  $ENV{AWS_WEB_IDENTITY_TOKEN_FILE} = '/tmp/token';

  $provider = eval { return Amazon::Credentials::Provider::WebIdentity->new; };

  ok !defined $provider, 'provider not returned';

  like $@, qr/AWS_ROLE_ARN/, 'missing role ARN croaks';

  return;
};

subtest 'web identity credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home       = tempdir( CLEANUP => 1 );
  my $token_file = "$home/token";

  write_file( $token_file, "fake-jwt\n" );

  $ENV{AWS_WEB_IDENTITY_TOKEN_FILE} = $token_file;

  $ENV{AWS_ROLE_ARN} = 'arn:aws:iam::123456789012:role/test';

  $ENV{AWS_REGION} = 'us-west-2';

  my $ua = TestUserAgent->new( response( credentials_response( 'access', 'secret', 'session-token' ) ) );

  my $provider = Amazon::Credentials::Provider::WebIdentity->new( user_agent => $ua );

  isa_ok $provider, 'Amazon::Credentials::Provider::WebIdentity';

  is $provider->get_aws_access_key_id, 'access', 'access key';

  is $provider->get_aws_secret_access_key, 'secret', 'secret key';

  is $provider->get_token, 'session-token', 'session token';

  is $provider->get_expiration, '2030-01-01T00:00:00Z', 'expiration';

  is $provider->get_source, 'web_identity', 'provider source';

  is $provider->get_region, 'us-west-2', 'region';

  is $provider->get_role_arn, 'arn:aws:iam::123456789012:role/test', 'role ARN retained';

  is $provider->get_token_file, $token_file, 'token file retained';

  ok $provider->is_refreshable, 'web identity credentials are refreshable';

  my $request = $ua->get_requests->[0];

  is $request->method, 'GET', 'STS request uses GET';

  like $request->uri->as_string, qr{\Ahttps://sts[.]us-west-2[.]amazonaws[.]com/}, 'regional STS endpoint';

  ok !$request->header('Authorization'), 'request is unsigned';

  return;
};

subtest 'default session name' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home       = tempdir( CLEANUP => 1 );
  my $token_file = "$home/token";

  write_file( $token_file, 'fake-jwt' );

  $ENV{AWS_WEB_IDENTITY_TOKEN_FILE} = $token_file;

  $ENV{AWS_ROLE_ARN} = 'arn:aws:iam::123456789012:role/test';

  my $ua = TestUserAgent->new( response( credentials_response( 'access', 'secret', 'token' ) ) );

  my $provider = Amazon::Credentials::Provider::WebIdentity->new( user_agent => $ua );

  is $provider->get_role_session_name, 'amazon-credentials-session', 'default role session name';

  like $ua->get_requests->[0]->uri->as_string,
    qr/RoleSessionName=amazon-credentials-session/,
    'default session name sent to STS';

  return;
};

subtest 'us-east-1 uses regional endpoint' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home       = tempdir( CLEANUP => 1 );
  my $token_file = "$home/token";

  write_file( $token_file, 'fake-jwt' );

  $ENV{AWS_WEB_IDENTITY_TOKEN_FILE} = $token_file;

  $ENV{AWS_ROLE_ARN} = 'arn:aws:iam::123456789012:role/test';

  $ENV{AWS_REGION} = 'us-east-1';

  my $ua = TestUserAgent->new( response( credentials_response( 'access', 'secret', 'token' ) ) );

  Amazon::Credentials::Provider::WebIdentity->new( user_agent => $ua );

  like $ua->get_requests->[0]->uri->as_string,
    qr{\Ahttps://sts[.]us-east-1[.]amazonaws[.]com/},
    'us-east-1 regional STS endpoint';

  return;
};

subtest 'STS error' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home       = tempdir( CLEANUP => 1 );
  my $token_file = "$home/token";

  write_file( $token_file, 'bad-jwt' );

  $ENV{AWS_WEB_IDENTITY_TOKEN_FILE} = $token_file;

  $ENV{AWS_ROLE_ARN} = 'arn:aws:iam::123456789012:role/test';

  my $ua = TestUserAgent->new(
    response(
      <<'XML',
<ErrorResponse>
  <Error>
    <Code>InvalidIdentityToken</Code>
    <Message>token is invalid</Message>
  </Error>
</ErrorResponse>
XML
      400
    )
  );

  my $provider = eval { return Amazon::Credentials::Provider::WebIdentity->new( user_agent => $ua ); };

  ok !defined $provider, 'provider not returned';

  like $@, qr/InvalidIdentityToken/, 'STS error croaks';

  return;
};

subtest 'refresh rereads token file' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home       = tempdir( CLEANUP => 1 );
  my $token_file = "$home/token";

  write_file( $token_file, 'token-1' );

  $ENV{AWS_WEB_IDENTITY_TOKEN_FILE} = $token_file;

  $ENV{AWS_ROLE_ARN} = 'arn:aws:iam::123456789012:role/test';

  my $ua = TestUserAgent->new(
    response( credentials_response( 'access-1', 'secret-1', 'session-1' ) ),
    response( credentials_response( 'access-2', 'secret-2', 'session-2' ) ),
  );

  my $provider = Amazon::Credentials::Provider::WebIdentity->new( user_agent => $ua );

  write_file( $token_file, 'token-2' );

  my $before = time;

  my $result = $provider->refresh_credentials;

  my $after = time;

  is $result, $provider, 'refresh returns provider';

  is $provider->get_aws_access_key_id, 'access-2', 'refreshed access key';

  is $provider->get_aws_secret_access_key, 'secret-2', 'refreshed secret key';

  is $provider->get_token, 'session-2', 'refreshed session token';

  like $ua->get_requests->[0]->uri->as_string, qr/WebIdentityToken=token-1/, 'initial token used';

  like $ua->get_requests->[1]->uri->as_string, qr/WebIdentityToken=token-2/, 'refreshed token reread from file';

  cmp_ok $provider->get_last_refreshed, '>=', $before, 'last_refreshed lower bound';

  cmp_ok $provider->get_last_refreshed, '<=', $after, 'last_refreshed upper bound';

  return;
};

done_testing;

1;

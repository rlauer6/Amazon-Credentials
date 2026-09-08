#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use Amazon::Credentials::HTTP::Response;
use Amazon::Credentials::Provider::Container;
use File::Temp qw(tempdir);
use Test::More;

{

  package TestUserAgent;

  use parent qw(Class::Accessor::Fast);

  __PACKAGE__->follow_best_practice;
  __PACKAGE__->mk_accessors(
    qw(
      request
      responses
    )
  );

  sub new {
    my ( $class, @responses ) = @_;

    return bless { responses => \@responses, }, $class;
  }

  sub request {
    my ( $self, $request ) = @_;

    $self->set_request($request);

    return shift @{ $self->get_responses };
  }
}

sub response {
  my ($json) = @_;

  return Amazon::Credentials::HTTP::Response->new(
    { content => $json,
      headers => { 'content-type' => 'application/json', },
      reason  => 'OK',
      status  => 200,
      success => 1,
    }
  );
}

sub clear_environment {
  delete @ENV{
    qw(
      AWS_CONTAINER_AUTHORIZATION_TOKEN
      AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE
      AWS_CONTAINER_CREDENTIALS_FULL_URI
      AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
    )
  };

  return;
}

subtest 'provider not applicable' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $provider = Amazon::Credentials::Provider::Container->new;

  ok !defined $provider, 'returns undef outside container environment';

  return;
};

subtest 'relative URI credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_CONTAINER_CREDENTIALS_RELATIVE_URI} = '/v2/credentials/test';

  my $ua = TestUserAgent->new(
    response(q|{"AccessKeyId":"access","SecretAccessKey":"secret","Token":"token","Expiration":"2030-01-01T00:00:00Z"}|) );

  my $provider = Amazon::Credentials::Provider::Container->new( user_agent => $ua );

  isa_ok $provider, 'Amazon::Credentials::Provider::Container';

  is $provider->get_source, 'container', 'provider source';

  is $provider->get_container_type, 'relative', 'relative container endpoint';

  is $provider->get_credential_uri, 'http://169.254.170.2/v2/credentials/test', 'credential URI';

  is $provider->get_aws_access_key_id, 'access', 'access key';

  is $provider->get_token, 'token', 'session token';

  is $ua->get_request->uri->as_string, 'http://169.254.170.2/v2/credentials/test', 'requested relative endpoint';

  ok $provider->is_refreshable, 'container credentials are refreshable';

  return;
};

subtest 'full URI credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_CONTAINER_CREDENTIALS_FULL_URI} = 'https://credentials.example.test/credentials';

  $ENV{AWS_CONTAINER_AUTHORIZATION_TOKEN} = 'authorization-token';

  my $ua = TestUserAgent->new( response(q|{"AccessKeyId":"access","SecretAccessKey":"secret","Token":"token"}|) );

  my $provider = Amazon::Credentials::Provider::Container->new( user_agent => $ua );

  is $provider->get_container_type, 'full', 'full container endpoint';

  is $ua->get_request->uri->as_string, 'https://credentials.example.test/credentials', 'requested full endpoint';

  is $ua->get_request->header('Authorization'), 'authorization-token', 'authorization token supplied';

  return;
};

subtest 'relative URI takes precedence' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_CONTAINER_CREDENTIALS_RELATIVE_URI} = '/relative';

  $ENV{AWS_CONTAINER_CREDENTIALS_FULL_URI} = 'https://credentials.example.test/full';

  my $ua = TestUserAgent->new( response(q|{"AccessKeyId":"access","SecretAccessKey":"secret"}|) );

  my $provider = Amazon::Credentials::Provider::Container->new( user_agent => $ua );

  is $provider->get_container_type, 'relative', 'relative URI takes precedence';

  return;
};

subtest 'unsafe full URI' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_CONTAINER_CREDENTIALS_FULL_URI} = 'http://example.com/credentials';

  my $provider = eval { return Amazon::Credentials::Provider::Container->new; };

  ok !defined $provider, 'provider not returned';

  like $@, qr/AWS_CONTAINER_CREDENTIALS_FULL_URI/, 'unsafe URI croaks';

  return;
};

subtest 'authorization token file' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $home = tempdir( CLEANUP => 1 );

  my $token_file = "$home/token";

  open my $fh, '>', $token_file
    or die "cannot write token file: $!";

  print {$fh} "file-token\n";

  close $fh;

  $ENV{AWS_CONTAINER_CREDENTIALS_FULL_URI} = 'https://credentials.example.test/credentials';

  $ENV{AWS_CONTAINER_AUTHORIZATION_TOKEN} = 'environment-token';

  $ENV{AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE} = $token_file;

  my $ua = TestUserAgent->new( response(q|{"AccessKeyId":"access","SecretAccessKey":"secret"}|) );

  Amazon::Credentials::Provider::Container->new( user_agent => $ua );

  is $ua->get_request->header('Authorization'), 'file-token', 'token file takes precedence';

  return;
};

subtest 'refresh credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_CONTAINER_CREDENTIALS_RELATIVE_URI} = '/credentials';

  my $ua = TestUserAgent->new(
    response(q|{"AccessKeyId":"access-1","SecretAccessKey":"secret-1","Token":"token-1"}|),
    response(q|{"AccessKeyId":"access-2","SecretAccessKey":"secret-2","Token":"token-2"}|),
  );

  my $provider = Amazon::Credentials::Provider::Container->new( user_agent => $ua );

  is $provider->get_aws_access_key_id, 'access-1', 'initial credentials';

  my $before = time;

  my $result = $provider->refresh_credentials;

  my $after = time;

  is $result, $provider, 'refresh returns provider';

  is $provider->get_aws_access_key_id, 'access-2', 'refreshed access key';

  is $provider->get_aws_secret_access_key, 'secret-2', 'refreshed secret key';

  is $provider->get_token, 'token-2', 'refreshed session token';

  cmp_ok $provider->get_last_refreshed, '>=', $before, 'last_refreshed lower bound';

  cmp_ok $provider->get_last_refreshed, '<=', $after, 'last_refreshed upper bound';

  return;
};

done_testing;

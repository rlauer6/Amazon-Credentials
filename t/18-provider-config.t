#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use File::Temp qw(tempdir);
use Test::More;

use Amazon::Credentials::Provider::Config;

sub write_file {
  my ( $path, $content ) = @_;

  open my $fh, '>', $path
    or die "cannot write $path: $!";

  print {$fh} $content;

  close $fh;

  return;
}

subtest 'profile not found' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sandbox]
region = us-west-2
CONFIG
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Config->new( profile => 'missing' );

  ok !defined $provider, 'returns undef when profile does not exist';

  return;
};

subtest 'profile has no static credentials' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sandbox]
region = us-west-2
credential_process = some-command
CONFIG
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Config->new( profile => 'sandbox' );

  ok !defined $provider, 'returns undef when profile does not contain static credentials';

  return;
};

subtest 'incomplete static credentials' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/credentials",
    <<'CREDENTIALS'
[sandbox]
aws_access_key_id = access-key
CREDENTIALS
  );

  local $ENV{HOME} = $home;

  my $provider = eval { return Amazon::Credentials::Provider::Config->new( profile => 'sandbox' ); };

  ok !defined $provider, 'provider not returned';
  like $@, qr/aws_secret_access_key/, 'missing secret key croaks';

  return;
};

subtest 'static credentials' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sandbox]
region = us-east-2
CONFIG
  );

  write_file(
    "$home/.aws/credentials",
    <<'CREDENTIALS'
[sandbox]
aws_access_key_id = access-key
aws_secret_access_key = secret-key
CREDENTIALS
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Config->new( profile => 'sandbox' );

  isa_ok $provider, 'Amazon::Credentials::Provider::Config';

  is $provider->get_aws_access_key_id,     'access-key', 'access key';
  is $provider->get_aws_secret_access_key, 'secret-key', 'secret key';
  is $provider->get_region,                'us-east-2',  'region';
  is $provider->get_source,                'config',     'provider source';

  ok !defined $provider->get_token,          'no session token';
  ok !defined $provider->get_last_refreshed, 'not refreshed';
  ok !$provider->is_refreshable,             'not refreshable';

  return;
};

subtest 'session credentials' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/credentials",
    <<'CREDENTIALS'
[sandbox]
aws_access_key_id = access-key
aws_secret_access_key = secret-key
aws_session_token = session-token
CREDENTIALS
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Config->new( profile => 'sandbox' );

  isa_ok $provider, 'Amazon::Credentials::Provider::Config';

  is $provider->get_token, 'session-token', 'session token';

  return;
};

subtest 'default profile' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/credentials",
    <<'CREDENTIALS'
[default]
aws_access_key_id = default-access
aws_secret_access_key = default-secret
CREDENTIALS
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Config->new;

  isa_ok $provider, 'Amazon::Credentials::Provider::Config';

  is $provider->get_aws_access_key_id, 'default-access', 'default profile selected';

  return;
};

subtest 'credentials file overrides config file' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sandbox]
aws_access_key_id = config-access
aws_secret_access_key = config-secret
region = us-east-1
CONFIG
  );

  write_file(
    "$home/.aws/credentials",
    <<'CREDENTIALS'
[sandbox]
aws_access_key_id = credentials-access
aws_secret_access_key = credentials-secret
CREDENTIALS
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Config->new( profile => 'sandbox' );

  is $provider->get_aws_access_key_id, 'credentials-access', 'credentials file access key takes precedence';

  is $provider->get_aws_secret_access_key, 'credentials-secret', 'credentials file secret key takes precedence';

  is $provider->get_region, 'us-east-1', 'config-only region preserved';

  return;
};

done_testing;

1;

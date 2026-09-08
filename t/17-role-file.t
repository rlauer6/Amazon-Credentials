#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use File::Temp qw(tempdir);
use Test::More;

{

  package TestProvider;

  use parent qw(Class::Accessor::Fast);

  use Role::Tiny::With;

  __PACKAGE__->follow_best_practice;
  __PACKAGE__->mk_accessors(qw(logger));

  with 'Amazon::Credentials::Role::File';

  sub get_logger {
    return TestLogger->new;
  }
}

{

  package TestLogger;

  sub new {
    return bless {}, shift;
  }

  sub debug {
    return;
  }
}

sub write_file {
  my ( $path, $content ) = @_;

  open my $fh, '>', $path
    or die "cannot write $path: $!";

  print {$fh} $content;

  close $fh;

  return;
}

subtest 'missing configuration files' => sub {
  my $home = tempdir( CLEANUP => 1 );

  local $ENV{HOME} = $home;

  my $provider = TestProvider->new;

  my $profile = $provider->_get_profile('default');

  ok !defined $profile, 'no profile when configuration files do not exist';

  return;
};

subtest 'default profile' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[default]
region = us-east-1
output = json
CONFIG
  );

  write_file(
    "$home/.aws/credentials",
    <<'CREDENTIALS'
[default]
aws_access_key_id = access-key
aws_secret_access_key = secret-key
CREDENTIALS
  );

  local $ENV{HOME} = $home;

  my $provider = TestProvider->new;

  my $profile = $provider->_get_profile('default');

  is_deeply(
    $profile,
    { aws_access_key_id     => 'access-key',
      aws_secret_access_key => 'secret-key',
      output                => 'json',
      region                => 'us-east-1',
    },
    'default profile merged from config and credentials'
  );

  return;
};

subtest 'named profile' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sandbox]
region = us-west-2
output = yaml
CONFIG
  );

  write_file(
    "$home/.aws/credentials",
    <<'CREDENTIALS'
[sandbox]
aws_access_key_id = sandbox-access
aws_secret_access_key = sandbox-secret
CREDENTIALS
  );

  local $ENV{HOME} = $home;

  my $provider = TestProvider->new;

  my $profile = $provider->_get_profile('sandbox');

  is_deeply(
    $profile,
    { aws_access_key_id     => 'sandbox-access',
      aws_secret_access_key => 'sandbox-secret',
      output                => 'yaml',
      region                => 'us-west-2',
    },
    'named profile merged across AWS section formats'
  );

  return;
};

subtest 'credentials file takes precedence' => sub {
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

  my $provider = TestProvider->new;

  my $profile = $provider->_get_profile('sandbox');

  is $profile->{aws_access_key_id}, 'credentials-access', 'credentials file access key takes precedence';

  is $profile->{aws_secret_access_key}, 'credentials-secret', 'credentials file secret key takes precedence';

  is $profile->{region}, 'us-east-1', 'config-only values preserved';

  return;
};

done_testing;

1;

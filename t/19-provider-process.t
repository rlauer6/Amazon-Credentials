#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use File::Temp qw(tempdir);
use Test::More;

use Amazon::Credentials::Provider::Process;

sub write_file {
  my ( $path, $content ) = @_;

  open my $fh, '>', $path
    or die "cannot write $path: $!";

  print {$fh} $content;

  close $fh;

  return;
}

sub write_process {
  my ( $path, $json ) = @_;

  write_file(
    $path,
    <<"PROCESS"
#!/usr/bin/env perl
print '$json';
PROCESS
  );

  chmod 0755, $path;

  return;
}

subtest 'profile not found' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Process->new( profile => 'missing' );

  ok !defined $provider, 'returns undef when profile does not exist';

  return;
};

subtest 'profile has no credential process' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  write_file(
    "$home/.aws/config",
    <<'CONFIG'
[profile sandbox]
region = us-east-1
CONFIG
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Process->new( profile => 'sandbox' );

  ok !defined $provider, 'returns undef when credential_process is absent';

  return;
};

subtest 'process credentials' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  my $process = "$home/credentials.pl";

  write_process( $process,
    q|{"Version":1,"AccessKeyId":"access-key","SecretAccessKey":"secret-key","SessionToken":"session-token","Expiration":"2030-01-01T00:00:00Z"}|
  );

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile sandbox]
region = us-west-2
credential_process = $process
CONFIG
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Process->new( profile => 'sandbox' );

  isa_ok $provider, 'Amazon::Credentials::Provider::Process';

  is $provider->get_aws_access_key_id,     'access-key',           'access key';
  is $provider->get_aws_secret_access_key, 'secret-key',           'secret key';
  is $provider->get_token,                 'session-token',        'session token';
  is $provider->get_expiration,            '2030-01-01T00:00:00Z', 'expiration';
  is $provider->get_region,                'us-west-2',            'profile region';
  is $provider->get_source,                'process',              'provider source';
  is $provider->get_process,               $process,               'process retained';
  is $provider->get_profile,               'sandbox',              'profile retained';

  ok $provider->is_refreshable,              'provider is refreshable';
  ok !defined $provider->get_last_refreshed, 'not yet refreshed';

  return;
};

subtest 'process region overrides profile' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  my $process = "$home/credentials.pl";

  write_process( $process, q|{"Version":1,"AccessKeyId":"access-key","SecretAccessKey":"secret-key","Region":"eu-west-1"}| );

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile sandbox]
region = us-west-2
credential_process = $process
CONFIG
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Process->new( profile => 'sandbox' );

  is $provider->get_region, 'eu-west-1', 'process region takes precedence';

  return;
};

subtest 'invalid process response' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  my $process = "$home/credentials.pl";

  write_process( $process, q|{"Version":1,"AccessKeyId":"access-key"}| );

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile sandbox]
credential_process = $process
CONFIG
  );

  local $ENV{HOME} = $home;

  my $provider = eval { return Amazon::Credentials::Provider::Process->new( profile => 'sandbox' ); };

  ok !defined $provider, 'provider not returned';
  like $@, qr/no SecretAccessKey/, 'incomplete process credentials croak';

  return;
};

subtest 'refresh credentials' => sub {
  my $home = tempdir( CLEANUP => 1 );

  mkdir "$home/.aws";

  my $process = "$home/credentials.pl";

  write_process( $process, q|{"Version":1,"AccessKeyId":"access-1","SecretAccessKey":"secret-1","SessionToken":"token-1"}| );

  write_file(
    "$home/.aws/config",
    <<"CONFIG"
[profile sandbox]
credential_process = $process
CONFIG
  );

  local $ENV{HOME} = $home;

  my $provider = Amazon::Credentials::Provider::Process->new( profile => 'sandbox' );

  is $provider->get_aws_access_key_id, 'access-1', 'initial credentials';

  write_process( $process, q|{"Version":1,"AccessKeyId":"access-2","SecretAccessKey":"secret-2","SessionToken":"token-2"}| );

  my $before = time;

  my $result = $provider->refresh_credentials;

  my $after = time;

  is $result, $provider, 'refresh returns provider';

  is $provider->get_aws_access_key_id,     'access-2', 'refreshed access key';
  is $provider->get_aws_secret_access_key, 'secret-2', 'refreshed secret key';
  is $provider->get_token,                 'token-2',  'refreshed token';

  cmp_ok $provider->get_last_refreshed, '>=', $before, 'last_refreshed lower bound';
  cmp_ok $provider->get_last_refreshed, '<=', $after,  'last_refreshed upper bound';

  return;
};

done_testing;

1;

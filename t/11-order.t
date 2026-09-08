use strict;
use warnings;

use lib qw(. lib);

use Test::More;
use Test::Output;

use Data::Dumper;
use English qw( -no_match_vars );
use UnitTest;

BEGIN {
  use_ok('Amazon::Credentials');
}

init_test;

my $creds = Amazon::Credentials->new( { order => 'file', } );

########################################################################
subtest 'creds in ini file' => sub {
########################################################################
  ok( ref $creds, 'found credentials in file' );

  is( $creds->get_aws_access_key_id, 'bar-aws-access-key-id', 'default profile' );

  $creds = eval { return Amazon::Credentials->new( order => 'blah' ); };

  like( $EVAL_ERROR, qr/unknown\s+credentials\s+plugin/xsm, 'only valid locations' );

  $creds
    = eval { return Amazon::Credentials->new( order => { this => 'blah' } ); };

  like( $EVAL_ERROR, qr/array\sref/xsm, 'only array refs or scalars' );
};

########################################################################
subtest 'AWS_PROFILE selects file resolver' => sub {
########################################################################
  local $ENV{AWS_PROFILE} = 'sandbox';

  my $credentials;

  stderr_like(
    sub { $credentials = Amazon::Credentials->new( raise_error => 0, ); },
    qr/no\s+credentials\s+available/xsm,
    'does not throw exception when credentials unavailable'
  );

  is( $credentials->get_profile, 'sandbox', 'AWS_PROFILE sets profile', );

  is_deeply( $credentials->_plugin_order, ['file'], 'AWS_PROFILE restricts discovery to file resolver', );
};

########################################################################
subtest 'explicit plugins override AWS_PROFILE' => sub {
########################################################################
  local $ENV{AWS_PROFILE}           = 'sandbox';
  local $ENV{AWS_ACCESS_KEY_ID}     = 'env-access-key';
  local $ENV{AWS_SECRET_ACCESS_KEY} = 'env-secret-key';

  my $credentials = Amazon::Credentials->new( plugins => ['env'], );

  is( $credentials->get_profile, 'sandbox', 'AWS_PROFILE still sets profile', );

  is_deeply( $credentials->_plugin_order, ['env'], 'explicit plugins override profile-driven file selection', );

  is( $credentials->get_aws_access_key_id, 'env-access-key', 'credentials resolved using explicit plugins', );

  is( $credentials->get_source, 'env', 'environment provider selected', );
};

########################################################################
subtest 'explicit plugins override explicit profile' => sub {
########################################################################
  local $ENV{AWS_ACCESS_KEY_ID}     = 'env-access-key';
  local $ENV{AWS_SECRET_ACCESS_KEY} = 'env-secret-key';

  my $credentials = Amazon::Credentials->new(
    profile => 'sandbox',
    plugins => ['env'],
  );

  is( $credentials->get_profile, 'sandbox', 'explicit profile retained', );

  is_deeply( $credentials->_plugin_order, ['env'], 'explicit plugins override profile-driven file selection', );

  is( $credentials->get_source, 'env', 'explicit plugin selected', );
};

########################################################################
subtest 'order cannot select disabled plugin' => sub {
########################################################################
  my $credentials;

  my $result = eval {
    $credentials = Amazon::Credentials->new(
      plugins => ['file'],
      order   => [ 'role', 'file' ],
    );

    return 1;
  };

  ok( !$credentials, 'credentials object not returned', );

  like( $EVAL_ERROR, qr/credentials plugin 'role' is not enabled/, 'order cannot select plugin disabled by plugins', );
};

done_testing;

1;

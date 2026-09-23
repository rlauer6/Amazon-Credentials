#!/usr/bin/env perl
use strict;
use warnings;

use Data::Dumper;
use Test::More;

use Amazon::Credentials::Provider;

my $access_key = 'TEST_ACCESS_KEY_DO_NOT_LEAK';
my $secret_key = 'TEST_SECRET_KEY_DO_NOT_LEAK';
my $token      = 'TEST_SESSION_TOKEN_DO_NOT_LEAK';

my $provider = Amazon::Credentials::Provider->new(
  { aws_access_key_id     => $access_key,
    aws_secret_access_key => $secret_key,
    token                 => $token,
    source                => 'test',
  }
);

########################################################################
subtest 'provider does not expose credentials in object dump' => sub {
########################################################################

  is( $provider->get_aws_access_key_id, $access_key, 'access key remains available through accessor', );

  is( $provider->get_aws_secret_access_key, $secret_key, 'secret access key remains available through accessor', );

  is( $provider->get_token, $token, 'session token remains available through accessor', );

  my $dump = Dumper($provider);

  unlike( $dump, qr/\Q$access_key\E/xsm, 'access key is not exposed by object dump', );

  unlike( $dump, qr/\Q$secret_key\E/xsm, 'secret access key is not exposed by object dump', );

  unlike( $dump, qr/\Q$token\E/xsm, 'session token is not exposed by object dump', );
};

########################################################################
subtest 'reset' => sub {
########################################################################

  $provider->set_aws_access_key_id('NEW_ACCESS_KEY_DO_NOT_LEAK');
  $provider->set_aws_secret_access_key('NEW_SECRET_KEY_DO_NOT_LEAK');
  $provider->set_token('NEW_TOKEN_DO_NOT_LEAK');

  my $dump = Dumper($provider);

  unlike( $dump, qr/NEW_ACCESS_KEY_DO_NOT_LEAK/xsm, 'updated access key is not exposed' );
  unlike( $dump, qr/NEW_SECRET_KEY_DO_NOT_LEAK/xsm, 'updated secret key is not exposed' );
  unlike( $dump, qr/NEW_TOKEN_DO_NOT_LEAK/xsm,      'updated token is not exposed' );

};

done_testing;

1;

#!/usr/bin/env perl

use strict;
use warnings;

use lib qw(.);

use Data::Dumper;
use English qw( -no_match_vars );
use Test::More;
use Test::Output;

use UnitTest;

BEGIN {
  use_ok('Amazon::Credentials');
}

init_test( test => '12-error.t' );

########################################################################
# raise_error => 1
########################################################################
local $ENV{AWS_EC2_METADATA_DISABLED} = 'true';

my $creds = eval { Amazon::Credentials->new( { profile => 'no profile', raise_error => 1, } ); };

like( $EVAL_ERROR, qr/^no\scredentials\savailable/xsm, 'raise_error => 1' )
  or do {
  diag( Dumper( [ error => $EVAL_ERROR, creds => $creds ] ) );
  BAIL_OUT($EVAL_ERROR);
  };

local $EVAL_ERROR = undef;

########################################################################
# raise_error => 0
########################################################################
stderr_like(
  sub {
    $creds = eval { Amazon::Credentials->new( { profile => 'no profile', raise_error => 0, } ); }
  },
  qr/^no\scredentials\savailable/xsm,
  'no raise error, but print error'
);

########################################################################
# raise_error => 0
########################################################################
ok( !$creds->get_aws_secret_access_key && !$EVAL_ERROR, 'raise_error => 0' )
  or do {
  diag(
    Dumper(
      [ creds             => $creds,
        error             => $EVAL_ERROR,
        secret_access_key => $creds->get_aws_secret_access_key
      ]
    )
  );
  BAIL_OUT;
  };

########################################################################
# raise_error => 0, print_error => 0
########################################################################
stderr_is(
  sub {
    $creds = eval {
      Amazon::Credentials->new(
        { profile     => 'no profile',
          raise_error => 0,
          print_error => 0,
          debug       => $ENV{DEBUG} ? 1 : 0,
        }
      );
    }
  },
  q{},
  'no print error'
);

stderr_like(
  sub {
    eval { Amazon::Credentials->new( profile => 'boo', ); }
  },
  qr/Can't\sexec\s"some_process_that_does_not_exist"/xsm,
  'die if cannot open process'
) or diag("error: $EVAL_ERROR");

########################################################################
# could not open
########################################################################
like( $EVAL_ERROR, qr/could\snot\sopen/xsm, 'bad process' )
  or diag( Dumper ["$EVAL_ERROR"] );

done_testing;

1;

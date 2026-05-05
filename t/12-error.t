#!/usr/bin/env perl

use strict;
use warnings;

use lib qw(.);

use Test::More tests => 6;
use Test::Output;

use Data::Dumper;
use English qw( -no_match_vars );

use UnitTest;

BEGIN {
  use_ok('Amazon::Credentials');
}

init_test( test => '12-error.t' );

########################################################################
# raise_error => 1
########################################################################
my $creds = eval { Amazon::Credentials->new( { profile => 'no profile', raise_error => 1, debug => $ENV{DEBUG} ? 1 : 0, } ); };

like( $EVAL_ERROR, qr/^no\scredentials\savailable/xsm, 'raise_error => 1' )
  or BAIL_OUT($EVAL_ERROR);

#Amazon::Credentials->new(
#  { profile     => 'no profile',
#    raise_error => 0,
#    print_error => 0,
#    debug       => $ENV{DEBUG} ? 1 : 0,
#  }
#);

local $EVAL_ERROR = undef;

########################################################################
# raise_error => 0
########################################################################
stderr_like(
  sub {
    $creds = eval { Amazon::Credentials->new( { profile => 'no profile', raise_error => 0, debug => $ENV{DEBUG} ? 1 : 0, } ); }
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

$creds = eval { return Amazon::Credentials->new( profile => 'boo', ); };

########################################################################
# could not open
########################################################################
like( $EVAL_ERROR, qr/could\snot\sopen/xsm, 'bad process' )
  or diag( Dumper ["$EVAL_ERROR"] );

1;

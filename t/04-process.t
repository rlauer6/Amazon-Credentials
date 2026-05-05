use strict;
use warnings;

BEGIN {
  use lib qw(. lib);
  use Test::More;

  use_ok('Amazon::Credentials');
}

use Cwd qw(abs_path);
use Cwd;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Temp qw(tempfile);
use UnitTest;

########################################################################
sub main {
########################################################################

  my ( $fh, $filename ) = tempfile( 'get-creds-XXXX', UNLINK => TRUE );

  {
    local $RS = undef;

    my $process = <DATA>;
    print {$fh} $process;
  }

  close $fh;
  chmod 0755, $filename;

  BAIL_OUT("cannot execute $filename")
    if !-x $filename;

  init_test( test => '04-process.t', vars => { process => abs_path($filename) } );

  my $creds = Amazon::Credentials->new(
    { profile => 'process',
      order   => [qw(file)],
      debug   => $ENV{DEBUG} ? TRUE : FALSE,
    }
  );

########################################################################
  # fin credentials
########################################################################

  ok( ref $creds, 'find credentials' );

########################################################################
  # aws_access_key_id
########################################################################

  like( $creds->get_aws_access_key_id, qr/^[[:upper:][:digit:]]+$/xsm, 'aws_access_key_id' );

########################################################################
  # aws_secret_access_key
########################################################################

  like( $creds->get_aws_secret_access_key, qr/^[[:lower:][:upper:][:digit:]+\/=]+$/xsm, 'aws_secret_access_key' )
    or diag( Dumper $creds );

########################################################################
  # token
########################################################################

  like( $creds->get_token, qr/^[[:lower:][:upper:][:digit:]\/+=]+$/xsm, 'token' )
    or diag( Dumper $creds );

  done_testing;

  return 0;
}

exit main();

1;

__DATA__
#!/usr/bin/env bash

cat <<EOF
{ "AccessKeyId" : "ABCDEFGHIJKLMNO", 
  "SecretAccessKey" : "aBcd09+/fjasdfadfHFD", 
  "SessionToken" : "U2FsdGVkX19SsBqHvBO2ZPMisxrK6Fnosq7P/BlMp/1+2Zr3QoWLtpqtbbezD4tfKUO9sYrEBHPm\nnP0ZLviKTSjTb0HDtgshiCod20cVYTSPZIX4uuMrz2PmTH69tMLCWSStxZBRYAd6mygtFSQC/KJ5\nepnjVilor4CCtMHSZ4BsnBHTiXUhNfF0otxpRC6mpnbPovD3H2YvsDQVmdDNSTfYvdivV8uO21Tm\nTwzDKWV1zC8jp0wLxgJYp/sHYBfoT7YDoy61Zt5+7PsGwBBQR7OPbVdIzEDAkVSvFP5rv/Mp02Fp\nDdqVR1eBszTuLrun7gg4rnF4YJURliyJOAXLJjF0yx8fqrkWiAX638xaHMsNO98YEzcESDHsp521\n0vWkWNTcnztFrymrlA+TMGsPfgn5IL3OwuqPO2URrQSaPMNhaG1nLkcvhI4Przv3LxbWrClEBhxm\niAUMgZ+o8k6ATlV9hFbivan4lMG5uECmYVfpjg5NQ/c2C9AaGsyaqhiESm8HE+flOIJEvTsMZXPV\nRswl+uQQ8lQc+qyAKAKiNLDMqf+WOIFKQD6T7/xsJ2aFKbZeYSNSb4dxqw1rWGJ9JA5/Iz7+2fKO\nHajUSsnNK0/vyfknf8yNaQBd8RPu/p3TMOz08qgevtEvmv9ox4eM4uVETlCV2DnQhEUkOheK3w4S\ng6twUmKJZzs6DcPC4xwdDApN8RDFY41+In4u1t8sxYhr0TNChgc/oSZ/QWh+OpdkQKfNnKxWh7bA\nA2yBUXAel6ovwafU6HW3rRmIB5zj+SRsimPEk4JRd6XdGZ6L9DC2bZ2LeG3+UfuFSqXkfoMD5Ksj\nuTuRvvwPa1wAh/dKOSNkvdHv6w1CdnvGY9RWCRGwhdK61bE6pTZj5OS5XA==", 
  "Expiration" : "2022-04-06T16:54:15+00:00"
}
EOF

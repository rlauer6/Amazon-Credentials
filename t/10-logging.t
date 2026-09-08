use strict;
use warnings;

use lib qw{ . lib };

use Test::More;
use Test::Output;
use Data::Dumper;
use English qw( -no_match_vars );
use UnitTest;
use JSON;

BEGIN {

  eval <<'END_OF_TEXT'; ## no critic
use Log::Log4perl;
use Log::Log4perl::Level;
Log::Log4perl->easy_init($DEBUG);
END_OF_TEXT

  if ($EVAL_ERROR) {
    plan skip_all => 'no Log::Log4perl available';
  }

  {
    no strict 'refs'; ## no critic

    *{'HTTP::Request::new'} = sub {
      my ( $class, $method, $url, $headers ) = @_;

      my $self = bless {
        method  => $method,
        url     => $url,
        headers => {},
      }, $class;

      if ($headers) {
        my @headers = @{$headers};

        while (@headers) {
          my ( $name, $value ) = splice @headers, 0, 2;
          $self->{headers}->{$name} = $value;
        }
      }

      return $self;
    };

    *{'HTTP::Request::clone'} = sub {
      my ($self) = @_;

      return bless { %{$self}, headers => { %{ $self->{headers} } }, }, ref $self;
    };

    *{'HTTP::Request::header_field_names'} = sub {
      my ($self) = @_;

      return keys %{ $self->{headers} };
    };

    *{'HTTP::Request::header'} = sub {
      my ( $self, $name, $value ) = @_;

      if ( @_ == 3 ) {
        $self->{headers}->{$name} = $value;
      }

      foreach my $key ( keys %{ $self->{headers} } ) {
        return $self->{headers}->{$key}
          if lc $key eq lc $name;
      }

      return;
    };

    *{'HTTP::Request::request'} = sub {
      return HTTP::Response->new;
    };
    {

      package HTTP::Response;

      sub new {
        my ( $class, $content ) = @_;

        return bless { content => $content, }, $class;
      }

      sub is_success {
        return 1;
      }

      sub content {
        my ($self) = @_;

        return $self->{content};
      }
    }

    *{'Amazon::Credentials::HTTP::UserAgent::new'}     = sub { bless {}, 'Amazon::Credentials::HTTP::UserAgent' };
    *{'Amazon::Credentials::HTTP::UserAgent::request'} = sub { HTTP::Response->new; };

  }

  use Module::Loaded;

  mark_as_loaded(HTTP::Request);
  mark_as_loaded(HTTP::Response);
  mark_as_loaded(Amazon::Credentials::HTTP::UserAgent);

  use_ok('Amazon::Credentials');
}

init_test;

my $stderr_from;

########################################################################
subtest 'logging' => sub {
########################################################################

  $stderr_from = stderr_from(
    sub {
      Amazon::Credentials->new(
        logger                => undef,
        debug                 => 1,  # default logger only used in debug mode
        aws_access_key_id     => 'TEST_ACCESS_KEY',
        aws_secret_access_key => 'TEST_SECRET_KEY',
      );
    }
  );

  ok( $stderr_from =~ /Amazon::Credentials::Logger/xsm, 'use default logger' )
    or diag($stderr_from);

  $stderr_from = stderr_from(
    sub {
      Amazon::Credentials->new(
        debug                 => 1,
        aws_access_key_id     => 'TEST_ACCESS_KEY',
        aws_secret_access_key => 'TEST_SECRET_KEY',
        logger                => Log::Log4perl->get_logger,

      );
    }
  );

  ok( $stderr_from =~ /using\sLog::Log4perl::Logger/xsm, 'use Log::Log4perl' )
    or diag($stderr_from);
};

########################################################################
subtest 'sanitize' => sub {
########################################################################
  my $creds = Amazon::Credentials->new(
    aws_access_key_id     => 'TEST_ACCESS_KEY',
    aws_secret_access_key => 'TEST_SECRET_KEY',
    debug                 => 0,
  );

  subtest 'hash and array structures' => sub {
    my $data = {
      aws_access_key_id     => 'AKIAEXAMPLE',
      aws_secret_access_key => 'secret',
      aws_session_token     => 'session-token',
      nested                => {
        accessToken => 'access-token',
        harmless    => 'visible',
      },
      headers => [
        Authorization => 'authorization-token',
        Accept        => 'application/json',
      ],
    };

    my $sanitized = $creds->sanitize($data);

    is( $sanitized->{aws_access_key_id}, '[REDACTED]', 'access key id redacted' );

    is( $sanitized->{aws_secret_access_key}, '[REDACTED]', 'secret access key redacted' );

    is( $sanitized->{aws_session_token}, '[REDACTED]', 'session token redacted' );

    is( $sanitized->{nested}->{accessToken}, '[REDACTED]', 'nested token redacted' );

    is( $sanitized->{nested}->{harmless}, 'visible', 'non-sensitive value preserved' );

    is( $sanitized->{headers}->[1], '[REDACTED]', 'authorization header value redacted' );

    is( $sanitized->{headers}->[3], 'application/json', 'non-sensitive header preserved' );

    is( $data->{aws_secret_access_key}, 'secret', 'original hash not modified' );
  };

  subtest 'HTTP::Request' => sub {
    my $request = HTTP::Request->new( GET => 'http://169.254.169.254/latest/meta-data/' );

    $request->header( Authorization              => 'authorization-token' );
    $request->header( 'X-Aws-Ec2-Metadata-Token' => 'imdsv2-token' );
    $request->header( Accept                     => '*/*' );

    my $sanitized = $creds->sanitize($request);

    isnt( $sanitized, $request, 'request is cloned' );

    is( $sanitized->header('Authorization'), '[REDACTED]', 'authorization header redacted' );

    is( $sanitized->header('X-Aws-Ec2-Metadata-Token'), '[REDACTED]', 'IMDSv2 token redacted' );

    is( $sanitized->header('Accept'), '*/*', 'non-sensitive header preserved' );

    is( $request->header('Authorization'), 'authorization-token', 'original request not modified' );
  };

  subtest 'HTTP response with JSON credentials' => sub {
    my $response = Amazon::Credentials::HTTP::Response->new(
      { status  => 200,
        content => encode_json(
          { AccessKeyId     => 'AKIAEXAMPLE',
            SecretAccessKey => 'secret',
            Token           => 'session-token',
            Expiration      => '2026-09-03T12:00:00Z',
          }
        ),
      }
    );

    my $sanitized = $creds->sanitize($response);
    my $content   = decode_json( $sanitized->content );

    is( $content->{AccessKeyId}, '[REDACTED]', 'response access key redacted' );

    is( $content->{SecretAccessKey}, '[REDACTED]', 'response secret key redacted' );

    is( $content->{Token}, '[REDACTED]', 'response token redacted' );

    is( $content->{Expiration}, '2026-09-03T12:00:00Z', 'non-sensitive response value preserved' );
  };

  subtest 'opaque HTTP response content' => sub {
    my $response = Amazon::Credentials::HTTP::Response->new(
      { status  => 200,
        content => 'raw-secret-token',
      }
    );

    my $sanitized = $creds->sanitize($response);

    is( $sanitized->content, '[REDACTED]', 'opaque response body redacted' );

    is( $response->content, 'raw-secret-token', 'original response not modified' );
  };
};

done_testing;

1;

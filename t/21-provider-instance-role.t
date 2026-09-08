#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use Amazon::Credentials::HTTP::Response;
use Amazon::Credentials::Provider::InstanceRole;
use English qw(-no_match_vars);
use HTTP::Response;
use Test::More;

{

  package TestUserAgent;

  use parent qw(Class::Accessor::Fast);

  __PACKAGE__->follow_best_practice;
  __PACKAGE__->mk_accessors(
    qw(
      requests
      responses
    )
  );

  sub new {
    my ( $class, @responses ) = @_;

    return bless {
      requests  => [],
      responses => \@responses,
    }, $class;
  }

  sub request {
    my ( $self, $request ) = @_;

    push @{ $self->get_requests }, $request;

    return shift @{ $self->get_responses };
  }
}

########################################################################
sub response {
########################################################################
  my ( $content, $status ) = @_;

  $status //= 200;

  return Amazon::Credentials::HTTP::Response->new(
    { content => $content,
      headers => {},
      reason  => $status == 200 ? 'OK' : 'ERROR',
      status  => $status,
      success => $status == 200 ? 1 : 0,
    }
  );
}

########################################################################
sub clear_environment {
########################################################################
  delete $ENV{AWS_EC2_METADATA_DISABLED};

  return;
}

########################################################################
subtest 'provider disabled' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_EC2_METADATA_DISABLED} = 'true';

  my $provider = Amazon::Credentials::Provider::InstanceRole->new;

  ok !defined $provider, 'returns undef when metadata is disabled';

  return;
};

########################################################################
subtest 'IMDSv1 credentials' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $ua
    = TestUserAgent->new( response("test-role\n"),
    response(q|{"AccessKeyId":"access","SecretAccessKey":"secret","Token":"token","Expiration":"2030-01-01T00:00:00Z"}|),
    );

  my $provider = Amazon::Credentials::Provider::InstanceRole->new(
    metadata_base_url => 'http://metadata.test/',
    user_agent        => $ua,
    imdsv2            => 'disabled',
  );

  isa_ok $provider, 'Amazon::Credentials::Provider::InstanceRole';

  is $provider->get_source, 'instance_role', 'provider source';

  is $provider->get_role, 'test-role', 'role name';

  is $provider->get_aws_access_key_id, 'access', 'access key';

  is $provider->get_aws_secret_access_key, 'secret', 'secret key';

  is $provider->get_token, 'token', 'session token';

  is $provider->get_expiration, '2030-01-01T00:00:00Z', 'expiration';

  is scalar @{ $ua->get_requests }, 2, 'two metadata requests';

  is $ua->get_requests->[0]->method, 'GET', 'role discovery uses GET';

  is $ua->get_requests->[0]->uri->as_string,
    'http://metadata.test/latest/meta-data/iam/security-credentials/',
    'role discovery endpoint';

  is $ua->get_requests->[1]->uri->as_string,
    'http://metadata.test/latest/meta-data/iam/security-credentials/test-role',
    'role credential endpoint';

  ok !$ua->get_requests->[0]->header('x-aws-ec2-metadata-token'), 'no IMDSv2 header on role request';

  ok $provider->is_refreshable, 'instance role credentials are refreshable';

  return;
};

########################################################################
subtest 'IMDSv2 credentials' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $ua = TestUserAgent->new(
    response('imdsv2-token'),
    response("test-role\n"), response(q|{"AccessKeyId":"access","SecretAccessKey":"secret","Token":"token"}|),
  );

  my $provider = Amazon::Credentials::Provider::InstanceRole->new(
    metadata_base_url => 'http://metadata.test/',
    user_agent        => $ua,
    imdsv2            => 'required',
  );

  isa_ok $provider, 'Amazon::Credentials::Provider::InstanceRole';

  is $provider->get_imdsv2_token, 'imdsv2-token', 'IMDSv2 token retained';

  is scalar @{ $ua->get_requests }, 3, 'token, role, and credential requests';

  is $ua->get_requests->[0]->method, 'PUT', 'token request uses PUT';

  is $ua->get_requests->[0]->uri->as_string, 'http://metadata.test/latest/api/token', 'token endpoint';

  is $ua->get_requests->[0]->header('x-aws-ec2-metadata-token-ttl-seconds'), 21_600, 'token TTL header';

  is $ua->get_requests->[1]->header('x-aws-ec2-metadata-token'), 'imdsv2-token', 'role request uses IMDSv2 token';

  is $ua->get_requests->[2]->header('x-aws-ec2-metadata-token'), 'imdsv2-token', 'credential request uses IMDSv2 token';

  return;
};

########################################################################
subtest 'no role found' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $ua = TestUserAgent->new( response( q{}, 404 ) );

  my $provider = Amazon::Credentials::Provider::InstanceRole->new(
    metadata_base_url => 'http://metadata.test/',
    user_agent        => $ua,
    imdsv2            => 'disabled',
  );

  ok !defined $provider, 'returns undef when no instance role is available';

  return;
};

########################################################################
subtest 'invalid credential response' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $ua = TestUserAgent->new( response('test-role'), response(q|{"AccessKeyId":"access"}|), );

  my $provider = eval {
    return Amazon::Credentials::Provider::InstanceRole->new(
      metadata_base_url => 'http://metadata.test/',
      user_agent        => $ua,
      imdsv2            => 'disabled',
    );
  };

  ok !defined $provider, 'provider not returned';

  like $@, qr/no SecretAccessKey/, 'incomplete role credentials croak';

  return;
};

########################################################################
subtest 'IMDSv2 required token failure' => sub {
########################################################################
  my $ua = TestUserAgent->new( HTTP::Response->new( 500, 'Internal Server Error' ), );

  my $provider;

  my $result = eval {
    $provider = Amazon::Credentials::Provider::InstanceRole->new(
      imdsv2     => 'required',
      user_agent => $ua,
    );

    return 1;
  };

  ok( !$provider, 'provider not returned' );

  like( $EVAL_ERROR, qr/could not retrieve IMDSv2 token/, 'required token failure croaks', );
};

########################################################################
subtest 'IMDSv2 preferred token failure falls back to IMDSv1' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $ua = TestUserAgent->new(
    HTTP::Response->new( 500, 'Internal Server Error' ),
    response("test-role\n"),
    response(q|{"AccessKeyId":"access","SecretAccessKey":"secret","Token":"token"}|),
  );

  my $provider = Amazon::Credentials::Provider::InstanceRole->new(
    metadata_base_url => 'http://metadata.test/',
    imdsv2            => 'preferred',
    user_agent        => $ua,
  );

  isa_ok( $provider, 'Amazon::Credentials::Provider::InstanceRole' );

  is( $provider->get_aws_access_key_id, 'access', 'IMDSv1 fallback credentials returned' );

  is( scalar @{ $ua->get_requests }, 3, 'token, role, and credential requests attempted' );

  is( $ua->get_requests->[0]->method, 'PUT', 'IMDSv2 token request attempted first' );

  is( $ua->get_requests->[1]->method, 'GET', 'role request falls back to IMDSv1' );

  is( $ua->get_requests->[2]->method, 'GET', 'credential request uses IMDSv1' );

  ok( !$ua->get_requests->[1]->header('x-aws-ec2-metadata-token'), 'no token header on IMDSv1 role request' );

  ok( !$ua->get_requests->[2]->header('x-aws-ec2-metadata-token'), 'no token header on IMDSv1 credential request' );

  return;
};

########################################################################
subtest 'refresh credentials' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $ua = TestUserAgent->new(
    response('test-role'),
    response(q|{"AccessKeyId":"access-1","SecretAccessKey":"secret-1","Token":"token-1"}|),
    response(q|{"AccessKeyId":"access-2","SecretAccessKey":"secret-2","Token":"token-2"}|),
  );

  my $provider = Amazon::Credentials::Provider::InstanceRole->new(
    metadata_base_url => 'http://metadata.test/',
    user_agent        => $ua,
    imdsv2            => 'disabled',
  );

  is $provider->get_aws_access_key_id, 'access-1', 'initial access key';

  my $before = time;

  my $result = $provider->refresh_credentials;

  my $after = time;

  is $result, $provider, 'refresh returns provider';

  is $provider->get_aws_access_key_id, 'access-2', 'refreshed access key';

  is $provider->get_aws_secret_access_key, 'secret-2', 'refreshed secret key';

  is $provider->get_token, 'token-2', 'refreshed session token';

  cmp_ok $provider->get_last_refreshed, '>=', $before, 'last_refreshed lower bound';

  cmp_ok $provider->get_last_refreshed, '<=', $after, 'last_refreshed upper bound';

  is scalar @{ $ua->get_requests }, 3, 'refresh does not rediscover role';

  is $ua->get_requests->[2]->uri->as_string,
    'http://metadata.test/latest/meta-data/iam/security-credentials/test-role',
    'refresh reuses resolved role';

  return;
};

########################################################################
subtest 'IMDSv2 refresh reuses token' => sub {
########################################################################
  local %ENV = %ENV;

  clear_environment();

  my $ua = TestUserAgent->new(
    response('imdsv2-token'),
    response('test-role'),
    response(q|{"AccessKeyId":"access-1","SecretAccessKey":"secret-1"}|),
    response(q|{"AccessKeyId":"access-2","SecretAccessKey":"secret-2"}|),
  );

  my $provider = Amazon::Credentials::Provider::InstanceRole->new(
    metadata_base_url => 'http://metadata.test/',
    user_agent        => $ua,
    imdsv2            => 'required',
  );

  $provider->refresh_credentials;

  is scalar @{ $ua->get_requests }, 4, 'refresh performs only credential request';

  is $ua->get_requests->[3]->header('x-aws-ec2-metadata-token'), 'imdsv2-token', 'refresh reuses IMDSv2 token';

  return;
};

########################################################################
subtest 'facade defaults IMDSv2 to preferred' => sub {
########################################################################
  my $ua = TestUserAgent->new(
    response('test-imdsv2-token'),
    response("instance-role\n"),
    response(q|{"AccessKeyId":"role-access","SecretAccessKey":"role-secret","Token":"role-token"}|),
  );

  require Amazon::Credentials;

  my $credentials = Amazon::Credentials->new(
    order      => 'role',
    user_agent => $ua,
  );

  is( $credentials->get_imdsv2, 'preferred', 'IMDSv2 defaults to preferred', );

  isa_ok( $credentials->get_provider, 'Amazon::Credentials::Provider::InstanceRole', );

  is( $credentials->get_provider->get_imdsv2, 'preferred', 'IMDSv2 policy propagated to instance role provider', );

  is( $ua->get_requests->[0]->method, 'PUT', 'preferred mode requests IMDSv2 token', );

  is( scalar @{ $ua->get_requests }, 3, 'token, role, and credential requests made', );
};

done_testing;

1;

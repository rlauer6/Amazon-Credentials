use strict;
use warnings;

use 5.010;

use Test::More;

use Amazon::Credentials::Provider::Env;

sub clear_environment {
  delete @ENV{
    qw(
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN
      AWS_REGION
      AWS_DEFAULT_REGION
    )
  };

  return;
}

subtest 'provider not applicable' => sub {
  local %ENV = %ENV;

  clear_environment();

  my $provider = Amazon::Credentials::Provider::Env->new;

  ok !defined $provider, 'returns undef when environment credentials are absent';

  return;
};

subtest 'incomplete credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_ACCESS_KEY_ID} = 'access-key';

  my $provider = eval { return Amazon::Credentials::Provider::Env->new; };

  ok !defined $provider, 'provider not returned';
  like $@, qr/AWS_SECRET_ACCESS_KEY is not set/, 'missing secret key croaks';

  clear_environment();

  $ENV{AWS_SECRET_ACCESS_KEY} = 'secret-key';

  $provider = eval { return Amazon::Credentials::Provider::Env->new; };

  ok !defined $provider, 'provider not returned';
  like $@, qr/AWS_ACCESS_KEY_ID is not set/, 'missing access key croaks';

  return;
};

subtest 'static environment credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_ACCESS_KEY_ID}     = 'access-key';
  $ENV{AWS_SECRET_ACCESS_KEY} = 'secret-key';

  my $before = time;

  my $provider = Amazon::Credentials::Provider::Env->new;

  my $after = time;

  isa_ok $provider, 'Amazon::Credentials::Provider::Env';

  is $provider->get_aws_access_key_id,     'access-key', 'access key';
  is $provider->get_aws_secret_access_key, 'secret-key', 'secret key';
  is $provider->get_source,                'env',        'provider source';

  ok !defined $provider->get_token,          'no session token';
  ok !defined $provider->get_expiration,     'no expiration';
  ok !defined $provider->get_region,         'no region';
  ok !defined $provider->get_last_refreshed, 'not refreshed';

  cmp_ok $provider->get_created_at, '>=', $before, 'created_at lower bound';
  cmp_ok $provider->get_created_at, '<=', $after,  'created_at upper bound';

  ok !$provider->is_refreshable, 'environment credentials are not refreshable';

  return;
};

subtest 'temporary environment credentials' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_ACCESS_KEY_ID}     = 'access-key';
  $ENV{AWS_SECRET_ACCESS_KEY} = 'secret-key';
  $ENV{AWS_SESSION_TOKEN}     = 'session-token';
  $ENV{AWS_REGION}            = 'us-west-2';

  my $provider = Amazon::Credentials::Provider::Env->new;

  isa_ok $provider, 'Amazon::Credentials::Provider::Env';

  is $provider->get_token,  'session-token', 'session token';
  is $provider->get_region, 'us-west-2',     'AWS_REGION';

  my $credentials = $provider->credentials;

  is_deeply(
    $credentials,
    { aws_access_key_id     => 'access-key',
      aws_secret_access_key => 'secret-key',
      region                => 'us-west-2',
      source                => 'env',
      token                 => 'session-token',
    },
    'normalized credentials'
  );

  return;
};

subtest 'AWS_DEFAULT_REGION fallback' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_ACCESS_KEY_ID}     = 'access-key';
  $ENV{AWS_SECRET_ACCESS_KEY} = 'secret-key';
  $ENV{AWS_DEFAULT_REGION}    = 'eu-west-1';

  my $provider = Amazon::Credentials::Provider::Env->new;

  is $provider->get_region, 'eu-west-1', 'AWS_DEFAULT_REGION';

  return;
};

subtest 'AWS_REGION precedence' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_ACCESS_KEY_ID}     = 'access-key';
  $ENV{AWS_SECRET_ACCESS_KEY} = 'secret-key';
  $ENV{AWS_REGION}            = 'us-east-2';
  $ENV{AWS_DEFAULT_REGION}    = 'eu-west-1';

  my $provider = Amazon::Credentials::Provider::Env->new;

  is $provider->get_region, 'us-east-2', 'AWS_REGION takes precedence';

  return;
};

subtest 'refresh not supported' => sub {
  local %ENV = %ENV;

  clear_environment();

  $ENV{AWS_ACCESS_KEY_ID}     = 'access-key';
  $ENV{AWS_SECRET_ACCESS_KEY} = 'secret-key';

  my $provider = Amazon::Credentials::Provider::Env->new;

  my $result = eval { return $provider->refresh_credentials; };

  ok !defined $result, 'no refresh result';
  like $@, qr/does not support credential refresh/, 'refresh croaks';

  return;
};

done_testing;

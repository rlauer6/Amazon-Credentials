use strict;
use warnings;

use 5.010;

use Test::More;
use POSIX qw(strftime);

use_ok('Amazon::Credentials');

{

  package TestSSOProvider;

  sub credentials {
    my ($self) = @_;

    return {
      aws_access_key_id     => $self->{aws_access_key_id},
      aws_secret_access_key => $self->{aws_secret_access_key},
      token                 => $self->{token},
      region                => $self->{region},
      source                => $self->{source},
    };
  }

  sub get_region     { return $_[0]->{region}; }
  sub get_source     { return $_[0]->{source}; }
  sub is_refreshable { return 1; }
}

{

  package Test::RefreshableProvider;

  sub new {
    my ($class) = @_;

    return bless {
      credentials => {
        aws_access_key_id     => 'OLD_ACCESS_KEY',
        aws_secret_access_key => 'OLD_SECRET_KEY',
        token                 => 'OLD_TOKEN',
      },
    }, $class;
  }

  sub is_refreshable {
    return 1;
  }

  sub refresh_credentials {
    my ($self) = @_;

    $self->{credentials} = {
      aws_access_key_id     => 'NEW_ACCESS_KEY',
      aws_secret_access_key => 'NEW_SECRET_KEY',
      token                 => 'NEW_TOKEN',
    };

    return $self;
  }

  sub credentials {
    my ($self) = @_;

    return $self->{credentials};
  }

  sub get_expiration {
    my ($self) = @_;

    return $self->{expiration};
  }

  sub set_expiration {
    my ( $self, $expiration ) = @_;

    $self->{expiration} = $expiration;

    return $self;
  }
}

my $credentials = Amazon::Credentials->new(
  aws_access_key_id     => 'TEST_ACCESS_KEY',
  aws_secret_access_key => 'TEST_SECRET_KEY',
);

isa_ok $credentials, 'Amazon::Credentials', 'credentials object';

my $provider = Test::RefreshableProvider->new;

$credentials->set_provider($provider);

my $expires_soon = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( time + 60 ) );

$credentials->set_expiration($expires_soon);

ok $credentials->is_token_expired, 'is_token_expired() - yes?';

my $expires_later = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( time + 600 ) );

$credentials->set_expiration($expires_later);

ok !$credentials->is_token_expired, 'is_token_expired() - no?';

my $expired = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( time - 60 ) );

$credentials->set_expiration($expired);

ok $credentials->is_token_expired, 'is_token_expired() - reset as expired';

$credentials->refresh_token;

is_deeply(
  $credentials->credential_keys,
  { AWS_ACCESS_KEY_ID     => 'NEW_ACCESS_KEY',
    AWS_SECRET_ACCESS_KEY => 'NEW_SECRET_KEY',
    AWS_SESSION_TOKEN     => 'NEW_TOKEN',
  },
  'refresh_token()',
);

########################################################################
subtest 'legacy SSO constructor options' => sub {
########################################################################
  require Amazon::Credentials::Provider::SSO;

  my %seen;

  ## no critic
  no warnings 'redefine';
  no warnings 'once';

  local *Amazon::Credentials::Provider::SSO::new = sub {
    my ( $class, @args ) = @_;

    my $options = ref $args[0] ? $args[0] : {@args};

    %seen = %{$options};

    return bless {
      aws_access_key_id     => 'sso-access',
      aws_secret_access_key => 'sso-secret',
      token                 => 'sso-token',
      region                => 'us-east-1',
      source                => 'sso',
      },
      'TestSSOProvider';
  };

  my $credentials = Amazon::Credentials->new(
    sso_role_name  => 'AWSAdministratorAccess',
    sso_account_id => '123456789012',
    sso_region     => 'us-east-1',
  );

  isa_ok( $credentials->get_provider, 'TestSSOProvider', );

  is( $seen{sso_role_name}, 'AWSAdministratorAccess', 'SSO role name propagated', );

  is( $seen{sso_account_id}, '123456789012', 'SSO account id propagated', );

  is( $seen{sso_region}, 'us-east-1', 'SSO region propagated', );

  is( $credentials->get_aws_access_key_id, 'sso-access', 'facade loaded SSO access key', );

  return;
};

done_testing;

1;

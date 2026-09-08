#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use Amazon::Credentials::HTTP::Response;
use English qw(-no_match_vars);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use Test::More;

{

  package TestSSOCache;

  use Role::Tiny::With;

  with 'Amazon::Credentials::Role::SSOCache';
}

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

sub response {
  my ( $content, $status ) = @_;

  $status //= 200;

  return Amazon::Credentials::HTTP::Response->new(
    { content => $content,
      headers => { 'content-type' => 'application/json', },
      reason  => $status == 200 ? 'OK' : 'ERROR',
      status  => $status,
      success => $status == 200 ? 1 : 0,
    }
  );
}

sub write_json {
  my ( $path, $data ) = @_;

  open my $fh, '>', $path
    or die "cannot write $path: $!";

  print {$fh} encode_json($data);

  close $fh;

  return;
}

sub cache_dir {
  my ($home) = @_;

  my $dir = "$home/.aws/sso/cache";

  make_path($dir);

  return $dir;
}

subtest 'cache key' => sub {
  my $cache = bless {}, 'TestSSOCache';

  is( $cache->_sso_cache_key('session-name'), Digest::SHA::sha1_hex('session-name'), 'cache key is sha1 of value' );

  return;
};

subtest 'valid cached token' => sub {
  my $home = tempdir( CLEANUP => 1 );
  my $dir  = cache_dir($home);

  my $cache = bless {}, 'TestSSOCache';

  my $key = $cache->_sso_cache_key('my-session');

  write_json(
    "$dir/$key.json",
    { accessToken => 'access-token',
      expiresAt   => '2099-01-01T00:00:00Z',
    }
  );

  my $token = $cache->_get_access_token(
    cache_key => $key,
    home      => $home,
    region    => 'us-east-1',
  );

  is( $token, 'access-token', 'valid cached token returned' );

  return;
};

subtest 'freshest cached token selected' => sub {
  my $home = tempdir( CLEANUP => 1 );
  my $dir  = cache_dir($home);

  my $cache = bless {}, 'TestSSOCache';

  write_json(
    "$dir/one.json",
    { accessToken => 'older-token',
      expiresAt   => '2098-01-01T00:00:00Z',
    }
  );

  write_json(
    "$dir/two.json",
    { accessToken => 'newer-token',
      expiresAt   => '2099-01-01T00:00:00Z',
    }
  );

  my $token = $cache->_get_access_token(
    home   => $home,
    region => 'us-east-1',
  );

  is( $token, 'newer-token', 'freshest cached token selected' );

  return;
};

subtest 'expired token refresh' => sub {
  my $home = tempdir( CLEANUP => 1 );
  my $dir  = cache_dir($home);

  my $cache = bless {}, 'TestSSOCache';

  my $key = $cache->_sso_cache_key('my-session');

  my $cache_file = "$dir/$key.json";

  write_json(
    $cache_file,
    { accessToken           => 'expired-token',
      clientId              => 'client-id',
      clientSecret          => 'client-secret',
      expiresAt             => '2020-01-01T00:00:00Z',
      refreshToken          => 'refresh-token',
      registrationExpiresAt => '2099-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new(
    response(
      encode_json(
        { accessToken  => 'refreshed-token',
          expiresIn    => 3600,
          refreshToken => 'rotated-refresh-token',
        }
      )
    )
  );

  my $token = $cache->_get_access_token(
    cache_key  => $key,
    home       => $home,
    region     => 'us-west-2',
    user_agent => $ua,
  );

  is( $token, 'refreshed-token', 'refreshed access token returned' );

  is( scalar @{ $ua->get_requests }, 1, 'one refresh request' );

  is( $ua->get_requests->[0]->method, 'POST', 'refresh uses POST' );

  is( $ua->get_requests->[0]->uri->as_string, 'https://oidc.us-west-2.amazonaws.com/token', 'regional OIDC endpoint' );

  my $content = decode_json( $ua->get_requests->[0]->content );

  is( $content->{grantType}, 'refresh_token', 'refresh grant type' );

  is( $content->{refreshToken}, 'refresh-token', 'refresh token sent' );

  open my $fh, '<', $cache_file
    or die "cannot read $cache_file: $!";

  my $saved;

  {
    local $RS = undef;
    $saved = <$fh>;
  }

  close $fh;

  my $saved_token = decode_json($saved);

  is( $saved_token->{accessToken}, 'refreshed-token', 'refreshed access token saved' );

  is( $saved_token->{refreshToken}, 'rotated-refresh-token', 'rotated refresh token saved' );

  return;
};

subtest 'expired registration cannot refresh' => sub {
  my $home = tempdir( CLEANUP => 1 );
  my $dir  = cache_dir($home);

  my $cache = bless {}, 'TestSSOCache';

  my $key = $cache->_sso_cache_key('my-session');

  write_json(
    "$dir/$key.json",
    { accessToken           => 'expired-token',
      clientId              => 'client-id',
      clientSecret          => 'client-secret',
      expiresAt             => '2020-01-01T00:00:00Z',
      refreshToken          => 'refresh-token',
      registrationExpiresAt => '2020-01-01T00:00:00Z',
    }
  );

  my $ua = TestUserAgent->new;

  my $token = $cache->_get_access_token(
    cache_key  => $key,
    home       => $home,
    region     => 'us-east-1',
    user_agent => $ua,
  );

  ok( !defined $token, 'expired registration cannot refresh' );

  is( scalar @{ $ua->get_requests }, 0, 'no refresh request attempted' );

  return;
};

subtest 'missing cache directory' => sub {
  my $home = tempdir( CLEANUP => 1 );

  my $cache = bless {}, 'TestSSOCache';

  my $token = eval { return $cache->_get_access_token( home => $home, region => 'us-east-1', ); };

  ok( !defined $token, 'no token returned' );

  like( $@, qr/no .*sso\/cache found/, 'missing cache directory croaks' );

  return;
};

done_testing;

#!/usr/bin/env perl

use strict;
use warnings;

use lib qw(. lib);

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use English qw(-no_match_vars);
use JSON;
use Test::More;

use Amazon::Credentials;
use Amazon::Credentials::HTTP::Response;

{

  package Local::SSORefreshUA;

  sub new {
    my ( $class, %args ) = @_;

    return bless { %args, requests => [] }, $class;
  }

  sub request {
    my ( $self, $request ) = @_;

    push @{ $self->{requests} }, $request;

    return Amazon::Credentials::HTTP::Response->new(
      { success => $self->{success} // 1,
        status  => $self->{status}  // 200,
        reason  => $self->{reason}  // 'OK',
        headers => { 'content-type' => 'application/json' },
        content => $self->{content},
      }
    );
  }

  sub requests {
    my ($self) = @_;

    return $self->{requests};
  }
}

########################################################################
sub _write_cache_entry {
########################################################################
  my ( $file, $data ) = @_;

  open my $fh, '>', $file
    or die "could not open $file for writing\n";

  print {$fh} encode_json($data);

  close $fh;

  return;
}

########################################################################
subtest 'refresh most recently expired token' => sub {
########################################################################
  my $home      = tempdir( CLEANUP => 1 );
  my $cache_dir = "$home/.aws/sso/cache";

  make_path($cache_dir);

  my $older_file = "$cache_dir/older.json";
  my $newer_file = "$cache_dir/newer.json";

  _write_cache_entry(
    $older_file,
    { accessToken           => 'access-old',
      expiresAt             => '2026-09-01T12:00:00Z',
      clientId              => 'client-old',
      clientSecret          => 'secret-old',
      refreshToken          => 'refresh-old',
      registrationExpiresAt => '2027-09-01T12:00:00Z',
      region                => 'us-west-2',
    }
  );

  _write_cache_entry(
    $newer_file,
    { accessToken           => 'access-newer',
      expiresAt             => '2026-09-02T12:00:00Z',
      clientId              => 'client-newer',
      clientSecret          => 'secret-newer',
      refreshToken          => 'refresh-newer',
      registrationExpiresAt => '2027-09-02T12:00:00Z',
      region                => 'us-east-2',
    }
  );

  my $ua = Local::SSORefreshUA->new(
    content => encode_json(
      { accessToken  => 'access-refreshed',
        expiresIn    => 3600,
        refreshToken => 'refresh-rotated',
        tokenType    => 'Bearer',
      }
    ),
  );

  my $access_token = Amazon::Credentials::_get_access_token(
    home       => $home,
    region     => 'us-east-1',
    user_agent => $ua,
  );

  is( $access_token,             'access-refreshed', 'returned refreshed access token' );
  is( scalar @{ $ua->requests }, 1,                  'one refresh request submitted' );

  my $request = $ua->requests->[0];

  is( $request->method,                 'POST',                                       'refresh uses POST' );
  is( $request->uri->as_string,         'https://oidc.us-east-2.amazonaws.com/token', 'uses selected token region' );
  is( $request->header('Content-Type'), 'application/json',                           'refresh content type' );

  my $request_content = decode_json( $request->content );

  is_deeply(
    $request_content,
    { clientId     => 'client-newer',
      clientSecret => 'secret-newer',
      grantType    => 'refresh_token',
      refreshToken => 'refresh-newer',
    },
    'refresh uses most recently expired cache entry'
  );

  open my $fh, '<', $newer_file
    or die "could not open $newer_file\n";
  local $RS = undef;
  my $newer = decode_json(<$fh>);
  close $fh;

  is( $newer->{accessToken},  'access-refreshed', 'cache access token updated' );
  is( $newer->{refreshToken}, 'refresh-rotated',  'rotated refresh token saved' );
  like( $newer->{expiresAt}, qr/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/xsm, 'cache expiration updated' );

  open $fh, '<', $older_file
    or die "could not open $older_file\n";
  local $RS = undef;
  my $older = decode_json(<$fh>);
  close $fh;

  is( $older->{accessToken}, 'access-old', 'older cache entry untouched' );
};

########################################################################
subtest 'valid newest token does not refresh' => sub {
########################################################################
  my $home      = tempdir( CLEANUP => 1 );
  my $cache_dir = "$home/.aws/sso/cache";

  make_path($cache_dir);

  _write_cache_entry(
    "$cache_dir/token.json",
    { accessToken  => 'access-valid',
      expiresAt    => '2099-09-02T12:00:00Z',
      clientId     => 'client',
      clientSecret => 'secret',
      refreshToken => 'refresh',
      region       => 'us-east-1',
    }
  );

  my $ua = Local::SSORefreshUA->new( content => '{}' );

  my $access_token = Amazon::Credentials::_get_access_token(
    home       => $home,
    region     => 'us-east-1',
    user_agent => $ua,
  );

  is( $access_token,             'access-valid', 'valid access token returned' );
  is( scalar @{ $ua->requests }, 0,              'refresh was not attempted' );
};

########################################################################
subtest 'expired registration cannot refresh' => sub {
########################################################################
  my $home      = tempdir( CLEANUP => 1 );
  my $cache_dir = "$home/.aws/sso/cache";

  make_path($cache_dir);

  _write_cache_entry(
    "$cache_dir/token.json",
    { accessToken           => 'access-expired',
      expiresAt             => '2026-09-02T12:00:00Z',
      clientId              => 'client',
      clientSecret          => 'secret',
      refreshToken          => 'refresh',
      registrationExpiresAt => '2026-09-02T13:00:00Z',
      region                => 'us-east-1',
    }
  );

  my $ua = Local::SSORefreshUA->new( content => '{}' );

  my $access_token = Amazon::Credentials::_get_access_token(
    home       => $home,
    region     => 'us-east-1',
    user_agent => $ua,
  );

  ok( !defined $access_token, 'no token returned' );
  is( scalar @{ $ua->requests }, 0, 'expired registration is not refreshed' );
};

done_testing;

1;

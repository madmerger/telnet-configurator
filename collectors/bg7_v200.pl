#!/usr/bin/env perl
# Tsuki Systems BG-7 gNodeB, software V200
# Standalone collector (predates lib/CBT's collectors); invoked by bin/cbt-collect as
#   bg7_v200.pl [OPTIONS] HOST PORT USER PASSWORD OUTFILE
# Options select the transport (default Telnet, as before):
#   --protocol telnet|ssh  --auth password|key  --key-file FILE
#   --known-hosts FILE  --host-key-check yes|accept-new  --timeout SEC  --log FILE  --verbose
# PASSWORD '-' reads the password (and key passphrase) from the environment
# (CBT_SESSION_PASSWORD, CBT_SESSION_KEY_PASSPHRASE) instead of the command line.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Getopt::Long;
use CBT::Session;

my %o = ( protocol => 'telnet', timeout => 20 );
GetOptions( \%o, 'protocol=s', 'auth=s', 'key-file=s', 'known-hosts=s', 'host-key-check=s', 'timeout=i', 'log=s',
    'verbose' )
  or die "bad options\n";
my ( $host, $port, $user, $pass, $outfile ) = @ARGV;
die "usage: $0 [OPTIONS] HOST PORT USER PASSWORD OUTFILE\n" unless $outfile;
my $passphrase;
if ( defined $pass && $pass eq '-' ) {
    $pass       = $ENV{CBT_SESSION_PASSWORD};
    $passphrase = $ENV{CBT_SESSION_KEY_PASSPHRASE};
}
my $step = $o{verbose} ? sub { local $| = 1; printf "    > %s\n", shift } : sub { };

my $s = CBT::Session->new(
    host            => $host,
    port            => $port,
    protocol        => $o{protocol},
    user            => $user,
    password        => $pass,
    auth            => $o{auth},
    key_file        => $o{'key-file'},
    key_passphrase  => $passphrase,
    known_hosts     => $o{'known-hosts'},
    host_key_check  => $o{'host-key-check'},
    timeout         => $o{timeout},
    log             => $o{log},
    prompt          => '/<[\w.-]+>$/',
    login_prompt    => '/login: ?$/',
    password_prompt => '/Password: ?$/',
);
if ( $s->preauthenticated ) {
    $step->("ssh authenticated ($o{auth})");
    $s->wait_prompt;
}
else {
    $step->('telnet login');
    $s->login( $user, $pass );
}

$step->('screen-length 0 temporary');
$s->cmd('screen-length 0 temporary');

open my $out, '>', $outfile or die "cannot write $outfile: $!\n";
for my $c ( 'display version', 'display current-configuration', 'display nr-cell all' ) {
    $step->($c);
    print $out "!! ===== $c =====\n", $s->cmd($c);
}
close $out;

$s->close('quit');
exit 0;

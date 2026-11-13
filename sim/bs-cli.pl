#!/usr/bin/env perl
# One simulated base-station CLI on stdin/stdout.
# Used as the sshd ForceCommand in lab/ssh and lab/docker: sshd has already
# authenticated the user, so the session starts at the device prompt.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use BSSim::CLI;

my %o = ( profile => 'ax4000-r5', hostname => 'BS-SIM', preauth => 1 );
GetOptions( \%o, 'profile=s', 'hostname=s', 'preauth!', 'echo!', 'enable-password=s' )
  or die "usage: $0 --profile NAME --hostname NAME [--no-preauth]\n";

my $cli = BSSim::CLI->new(
    profile  => $o{profile},
    hostname => $o{hostname},
    preauth  => $o{preauth},
    echo     => $o{echo},
    ( defined $o{'enable-password'} ? ( enable_password => $o{'enable-password'} ) : () ),
);
$| = 1;
binmode STDIN;
binmode STDOUT;
syswrite STDOUT, $cli->start;
while ( !$cli->closed ) {
    my $n = sysread STDIN, my $buf, 4096;
    last unless $n;
    my $out = $cli->feed($buf);
    syswrite STDOUT, $out if length $out;
}
exit 0;

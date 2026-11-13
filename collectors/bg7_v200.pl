#!/usr/bin/env perl
# Tsuki Systems BG-7 gNodeB, software V200
# Standalone collector (predates lib/CBT); invoked by bin/cbt-collect as
#   bg7_v200.pl HOST PORT USER PASSWORD OUTFILE
use strict;
use warnings;
use Net::Telnet;

my ( $host, $port, $user, $pass, $outfile ) = @ARGV;
die "usage: $0 HOST PORT USER PASSWORD OUTFILE\n" unless $outfile;

my $t = Net::Telnet->new( Timeout => 20, Prompt => '/<[\w.-]+>$/' );
$t->open( Host => $host, Port => $port || 23 );
$t->waitfor('/login: ?$/');
$t->print($user);
$t->waitfor('/Password: ?$/');
$t->print($pass);
$t->waitfor( $t->prompt );

$t->cmd('screen-length 0 temporary');

open my $out, '>', $outfile or die "cannot write $outfile: $!\n";
for my $c ( 'display version', 'display current-configuration', 'display nr-cell all' ) {
    my @lines = $t->cmd($c);
    s/\r//g for @lines;
    print $out "!! ===== $c =====\n", @lines;
}
close $out;

$t->print('quit');
$t->close;
exit 0;

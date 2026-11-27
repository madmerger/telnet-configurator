#!/usr/bin/env perl
# Tsuki Systems BG-7 gNodeB, software V200
# Standalone collector (predates lib/CBT); invoked by bin/cbt-collect as
#   bg7_v200.pl [--protocol telnet|ssh] [--auth password|key] [--key-file FILE]
#               [--host-key-check yes|accept-new|no] [--known-hosts FILE]
#               HOST PORT USER PASSWORD OUTFILE
# An empty PASSWORD is read from $CBT_COLLECT_PASSWORD (keeps it out of the process list).
# Over SSH, sshd authenticates the user (password or key), so there is no login: prompt.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Getopt::Long qw(:config require_order);    # a password starting with '-' stays positional
use Net::Telnet;

my %o = ( protocol => 'telnet', auth => 'password' );
GetOptions( \%o, 'protocol=s', 'auth=s', 'key-file=s', 'host-key-check=s', 'known-hosts=s' )
  or die "usage: $0 [options] HOST PORT USER PASSWORD OUTFILE\n";
die "usage: $0 [options] HOST PORT USER PASSWORD OUTFILE\n" unless @ARGV == 5 && length $ARGV[4];
my ( $host, $port, $user, $pass, $outfile ) = @ARGV;
$pass = $ENV{CBT_COLLECT_PASSWORD} // '' unless length $pass;

my $prompt = '/<[\w.-]+>$/';
my ( $t, $ssh );
if ( $o{protocol} eq 'ssh' ) {
    require CBT::SSH;
    $ssh = CBT::SSH->open(
        host           => $host,
        port           => $port,
        user           => $user,
        password       => $pass,
        auth           => $o{auth},
        key_file       => $o{'key-file'},
        host_key_check => $o{'host-key-check'},
        known_hosts    => $o{'known-hosts'},
        timeout        => 20,
        prompt         => $prompt,
    );
    $t = $ssh->telnet;
    $t->waitfor( $t->prompt );
}
elsif ( $o{protocol} eq 'telnet' ) {
    $t = Net::Telnet->new( Timeout => 20, Prompt => $prompt );
    $t->open( Host => $host, Port => $port || 23 );
    $t->waitfor('/login: ?$/');
    $t->print($user);
    $t->waitfor('/Password: ?$/');
    $t->print($pass);
    $t->waitfor( $t->prompt );
}
else {
    die "unknown protocol '$o{protocol}'\n";
}

$t->cmd('screen-length 0 temporary');

open my $out, '>', $outfile or die "cannot write $outfile: $!\n";
for my $c ( 'display version', 'display current-configuration', 'display nr-cell all' ) {
    my @lines = $t->cmd($c);
    s/\r//g for @lines;
    print $out "!! ===== $c =====\n", @lines;
}
close $out;

$t->print('quit');
$ssh ? $ssh->close : $t->close;
exit 0;

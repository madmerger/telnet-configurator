#!/usr/bin/env perl
# Tsuki Systems BG-7 gNodeB, software V200
# Standalone collector (predates lib/CBT); invoked by bin/cbt-collect as
#   bg7_v200.pl [--ssh [--key FILE] [--known-hosts FILE]] HOST PORT USER PASSWORD OUTFILE
# With --ssh and no --key, PASSWORD is used for SSH password authentication.
use strict;
use warnings;
use Getopt::Long;
use Net::Telnet;

my ( $ssh_mode, $key, $known_hosts );
GetOptions( 'ssh' => \$ssh_mode, 'key=s' => \$key, 'known-hosts=s' => \$known_hosts ) or die "bad options\n";
my ( $host, $port, $user, $pass, $outfile ) = @ARGV;
die "usage: $0 [--ssh [--key FILE] [--known-hosts FILE]] HOST PORT USER PASSWORD OUTFILE\n" unless $outfile;

my ( $t, $ssh, $pid );
if ($ssh_mode) {
    require Net::OpenSSH;
    my @kh = $known_hosts ? ( -o => "UserKnownHostsFile=$known_hosts", -o => 'StrictHostKeyChecking=accept-new', -o => 'LogLevel=ERROR' ) : ();
    $ssh = Net::OpenSSH->new(
        $host, port => $port || 22, user => $user, timeout => 20,
        ( $key ? ( key_path => $key, master_opts => [ @kh, -o => 'PasswordAuthentication=no' ] )
               : ( password => $pass, master_opts => [ @kh, -o => 'PubkeyAuthentication=no' ] ) ),
    );
    die "ssh connect to $host:$port failed: " . $ssh->error . "\n" if $ssh->error;
    ( my $pty, $pid ) = $ssh->open2pty or die "ssh session failed: " . $ssh->error . "\n";
    $t = Net::Telnet->new( Fhopen => $pty, Telnetmode => 0, Binmode => 1, Output_record_separator => "\r", Cmd_remove_mode => 1,
                           Timeout => 20, Prompt => '/<[\w.-]+>$/' );
    $t->waitfor( $t->prompt );
}
else {
    $t = Net::Telnet->new( Timeout => 20, Prompt => '/<[\w.-]+>$/' );
    $t->open( Host => $host, Port => $port || 23 );
    $t->waitfor('/login: ?$/');
    $t->print($user);
    $t->waitfor('/Password: ?$/');
    $t->print($pass);
    $t->waitfor( $t->prompt );
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
$t->close;
waitpid $pid, 0 if $pid;
exit 0;

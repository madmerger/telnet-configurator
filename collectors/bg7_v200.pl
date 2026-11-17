#!/usr/bin/env perl
# Tsuki Systems BG-7 gNodeB, software V200
# Standalone collector (predates lib/CBT); invoked by bin/cbt-collect as
#   bg7_v200.pl [OPTIONS] HOST PORT USER PASSWORD OUTFILE
# PASSWORD '-' reads it from $CBT_DEVICE_PASSWORD (keeps it off the command line).
# Options:
#   --protocol telnet|ssh            (default telnet)
#   --auth password|publickey        ssh authentication (default password)
#   --key-file F --known-hosts F --host-key-check yes|accept-new|no --log F
#   --timeout SEC                    (default 20)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Getopt::Long;

my %o = ( protocol => 'telnet', auth => 'password', 'host-key-check' => 'yes', timeout => 20 );
GetOptions( \%o, 'protocol=s', 'auth=s', 'key-file=s', 'known-hosts=s', 'host-key-check=s', 'log=s', 'timeout=i' )
  or usage();
my ( $host, $port, $user, $pass, $outfile ) = @ARGV;
usage() unless $outfile;
$pass = $ENV{CBT_DEVICE_PASSWORD} // '' if $pass eq '-';

my $prompt   = '/<[\w.-]+>$/';
my @commands = ( 'display version', 'display current-configuration', 'display nr-cell all' );
my @sections;

if ( $o{protocol} eq 'ssh' ) {
    require CBT::Session::SSH;
    my $s = CBT::Session::SSH->new(
        host           => $host,
        port           => $port || 22,
        user           => $user,
        password       => $pass,
        auth           => $o{auth},
        key_file       => $o{'key-file'},
        known_hosts    => $o{'known-hosts'},
        host_key_check => $o{'host-key-check'},
        timeout        => $o{timeout},
        prompt         => $prompt,
        log            => $o{log},
    );
    $s->cmd('screen-length 0 temporary');
    @sections = map { [ $_, $s->cmd($_) ] } @commands;
    $s->close('quit');
}
elsif ( $o{protocol} eq 'telnet' ) {
    require Net::Telnet;
    my $t = Net::Telnet->new( Timeout => $o{timeout}, Prompt => $prompt );
    $t->open( Host => $host, Port => $port || 23 );
    $t->waitfor('/login: ?$/');
    $t->print($user);
    $t->waitfor('/Password: ?$/');
    $t->print($pass);
    $t->waitfor( $t->prompt );

    $t->cmd('screen-length 0 temporary');

    for my $c (@commands) {
        my @lines = $t->cmd($c);
        s/\r//g for @lines;
        push @sections, [ $c, join '', @lines ];
    }

    $t->print('quit');
    $t->close;
}
else {
    die "unknown protocol '$o{protocol}'\n";
}

open my $out, '>', $outfile or die "cannot write $outfile: $!\n";
print $out "!! ===== $_->[0] =====\n", $_->[1] for @sections;
close $out;
exit 0;

sub usage { die "usage: $0 [--protocol telnet|ssh] [--auth password|publickey] [--key-file F] HOST PORT USER PASSWORD OUTFILE\n" }

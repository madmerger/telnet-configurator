#!/usr/bin/env perl
# Telnet base-station simulator: serves one simulated device per TCP port on
# localhost, so the collector can be tested without reaching real equipment.
#
#   perl sim/bs-sim.pl                      # default lab (sim/devices.conf)
#   perl sim/bs-sim.pl --device ax4000-r5:2301:TKY-ENB-0001 --device ...
#   telnet 127.0.0.1 2301                   # cbtadmin / cbt-pass, enable: cbt-enable
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use IO::Socket::INET;
use IO::Select;
use POSIX ();
use BSSim::CLI;

my %o = ( listen => '127.0.0.1', config => "$FindBin::Bin/devices.conf" );
GetOptions( \%o, 'listen=s', 'device=s@', 'config=s', 'pidfile=s', 'daemon', 'quiet' )
  or die "usage: $0 [--listen ADDR] [--device PROFILE:PORT:HOSTNAME ...] [--pidfile F] [--daemon]\n";

my @devices = @{ $o{device} || [] };
if ( !@devices ) {
    open my $fh, '<', $o{config} or die "cannot read $o{config}: $!\n";
    while (<$fh>) {
        next if /^\s*(#|$)/;
        my ( $profile, $port, $host ) = split ' ';
        push @devices, "$profile:$port:$host";
    }
}

my ( %by_sock, @socks );
for my $d (@devices) {
    my ( $profile, $port, $host ) = split /:/, $d;
    BSSim::Profile->get($profile);
    my $s = IO::Socket::INET->new( LocalAddr => $o{listen}, LocalPort => $port, Listen => 16, ReuseAddr => 1 )
      or die "cannot listen on $o{listen}:$port: $!\n";
    $by_sock{"$s"} = { profile => $profile, port => $port, host => $host };
    push @socks, $s;
    printf "bs-sim: %-14s %-10s telnet://%s:%d\n", $host, $profile, $o{listen}, $port unless $o{quiet};
}

if ( $o{daemon} ) {
    defined( my $pid = fork ) or die "fork: $!";
    exit 0 if $pid;
    POSIX::setsid();
    open STDIN,  '<', '/dev/null';
    open STDOUT, '>', '/dev/null';
    open STDERR, '>', '/dev/null';
}
if ( $o{pidfile} ) {
    open my $pf, '>', $o{pidfile} or die "pidfile: $!";
    print $pf "$$\n";
    close $pf;
}

$SIG{CHLD} = sub { 1 while waitpid( -1, POSIX::WNOHANG() ) > 0 };
$SIG{TERM} = $SIG{INT} = sub { unlink $o{pidfile} if $o{pidfile}; exit 0 };

my $sel = IO::Select->new(@socks);
while (1) {
    for my $ready ( $sel->can_read ) {
        my $client = $ready->accept or next;
        my $dev    = $by_sock{"$ready"};
        my $pid    = fork;
        if ( !defined $pid ) { close $client; next }
        if ( $pid == 0 ) {
            $_->close for @socks;
            serve( $client, $dev );
            exit 0;
        }
        close $client;
    }
}

use constant { IAC => 255, DONT => 254, DO => 253, WONT => 252, WILL => 251, SB => 250, SE => 240 };
use constant { OPT_ECHO => 1, OPT_SGA => 3 };

sub serve {
    my ( $sock, $dev ) = @_;
    binmode $sock;
    $sock->autoflush(1);
    my $cli = BSSim::CLI->new( profile => $dev->{profile}, hostname => $dev->{host} );

    # Offer server-side echo like real equipment; clients that refuse it
    # (Net::Telnet does by default) do their own echo.
    syswrite $sock, pack( 'C*', IAC, WILL, OPT_ECHO, IAC, WILL, OPT_SGA );
    syswrite $sock, $cli->start;

    my $pending = '';
    my $idle    = IO::Select->new($sock);
    while ( !$cli->closed ) {
        last unless $idle->can_read(600);
        my $n = sysread $sock, my $buf, 4096;
        last unless $n;
        $pending .= $buf;
        my $data = '';
        while ( length $pending ) {
            my $b = ord $pending;
            if ( $b != IAC ) { $data .= substr $pending, 0, 1, ''; next }
            last if length $pending < 2;
            my $cmd = ord substr $pending, 1, 1;
            if ( $cmd == IAC ) { $data .= chr 255; substr $pending, 0, 2, ''; next }
            if ( $cmd == SB ) {
                my $end = index $pending, pack( 'C2', IAC, SE );
                last if $end < 0;
                substr $pending, 0, $end + 2, '';
                next;
            }
            if ( $cmd >= WILL && $cmd <= DONT ) {
                last if length $pending < 3;
                my $opt = ord substr $pending, 2, 1;
                substr $pending, 0, 3, '';
                if    ( $opt == OPT_ECHO && $cmd == DO )   { $cli->set_echo(1) }
                elsif ( $opt == OPT_ECHO && $cmd == DONT ) { $cli->set_echo(0) }
                elsif ( $cmd == WILL ) { syswrite $sock, pack( 'C3', IAC, DONT, $opt ) }
                next;
            }
            substr $pending, 0, 2, '';
        }
        my $out = $cli->feed($data);
        if ( length $out ) {
            $out =~ s/\xff/\xff\xff/g;
            syswrite $sock, $out;
        }
    }
    close $sock;
}

#!/usr/bin/env perl
# One simulated base-station CLI on stdin/stdout.
# Used as the sshd ForceCommand in lab/ssh and lab/docker: sshd has already
# authenticated the user, so the session starts at the device prompt.
# When stdin is a terminal (ssh -t), it is switched to raw mode and the CLI does
# its own echo, like a real device: no tty echo of passwords, no CR/LF rewriting.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use POSIX ();
use BSSim::CLI;

my %o = ( profile => 'ax4000-r5', hostname => 'BS-SIM', preauth => 1 );
GetOptions( \%o, 'profile=s', 'hostname=s', 'preauth!', 'echo!', 'enable-password=s' )
  or die "usage: $0 --profile NAME --hostname NAME [--no-preauth]\n";

my $saved_tty;
if ( -t STDIN ) {
    my $tio = POSIX::Termios->new;
    if ( $tio->getattr(0) ) {
        $saved_tty = POSIX::Termios->new;
        $saved_tty->getattr(0);
        $tio->setlflag( $tio->getlflag & ~( POSIX::ECHO() | POSIX::ECHONL() | POSIX::ICANON() | POSIX::ISIG() | POSIX::IEXTEN() ) );
        $tio->setiflag( $tio->getiflag & ~( POSIX::ICRNL() | POSIX::INLCR() | POSIX::IGNCR() | POSIX::IXON() ) );
        $tio->setoflag( $tio->getoflag & ~POSIX::OPOST() );
        $tio->setcc( POSIX::VMIN(), 1 );
        $tio->setcc( POSIX::VTIME(), 0 );
        $tio->setattr( 0, POSIX::TCSANOW() );
        $o{echo} //= 1;
    }
}
END { $saved_tty->setattr( 0, POSIX::TCSANOW() ) if $saved_tty }

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

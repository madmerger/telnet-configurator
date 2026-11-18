package Net::Telnet;
# Offline fallback for CPAN Net::Telnet, loaded only when the real module is not
# installed (it is appended to @INC). Implements just what this repo uses:
# new/open/waitfor/print/cmd/prompt/errmsg/close. Install Net::Telnet for production.
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;

our $VERSION = '3.05_shim';

sub new {
    my ( $class, %a ) = @_;
    my $self = bless {
        timeout => $a{Timeout} // 10,
        errmode => $a{Errmode} // 'die',
        prompt  => $a{Prompt}  // '/[\$%#>] $/',
        buf     => '', errmsg => '', eof => 0,
    }, $class;
    if ( my $f = $a{Input_log} ) {
        open my $fh, '>', $f or return $self->_err("cannot open input log $f: $!");
        binmode $fh; $fh->autoflush(1);
        $self->{ilog} = $fh;
    }
    $self->open( Host => $a{Host}, Port => $a{Port} ) if $a{Host};
    return $self;
}

sub _err {
    my ( $self, $msg ) = @_;
    $self->{errmsg} = $msg;
    die "$msg\n" if $self->{errmode} eq 'die';
    return;
}

sub errmsg { $_[0]{errmsg} }

sub prompt {
    my ( $self, $p ) = @_;
    my $old = $self->{prompt};
    $self->{prompt} = $p if defined $p;
    return $old;
}

sub open {
    my ( $self, %a ) = @_;
    my $port = $a{Port} || 23;
    my $s = IO::Socket::INET->new( PeerAddr => $a{Host}, PeerPort => $port, Timeout => $self->{timeout} )
      or return $self->_err("unknown remote host or connection refused: $a{Host}:$port: $!");
    binmode $s; $s->autoflush(1);
    @$self{qw(sock buf eof errmsg)} = ( $s, '', 0, '' );
    return 1;
}

sub print {
    my ( $self, @args ) = @_;
    my $data = join( '', @args ) . "\n";
    $data =~ s/\xff/\xff\xff/g;
    $data =~ s/\n/\r\n/g;
    return $self->_err('write error: not connected') unless $self->{sock};
    syswrite( $self->{sock}, $data ) // return $self->_err("write error: $!");
    return 1;
}

# Read from socket, handle telnet negotiation (refuse every option, as Net::Telnet does by default).
sub _fill {
    my ( $self, $wait ) = @_;
    return 0 if $self->{eof};
    my $sel = IO::Select->new( $self->{sock} );
    return 0 unless $sel->can_read($wait);
    my $n = sysread $self->{sock}, my $raw, 4096;
    if ( !$n ) { $self->{eof} = 1; return 0 }
    $raw = $self->{rawpend} . $raw if defined $self->{rawpend};
    $self->{rawpend} = undef;
    my $out = '';
    while ( length $raw ) {
        my $c = ord $raw;
        if ( $c != 255 ) { $out .= substr $raw, 0, 1, ''; next }
        if ( length $raw < 2 ) { $self->{rawpend} = $raw; last }
        my $cmd = ord substr $raw, 1, 1;
        if ( $cmd == 255 ) { $out .= "\xff"; substr $raw, 0, 2, ''; next }
        if ( $cmd >= 251 && $cmd <= 254 ) {
            if ( length $raw < 3 ) { $self->{rawpend} = $raw; last }
            my $opt = ord substr $raw, 2, 1;
            substr $raw, 0, 3, '';
            my $reply = $cmd == 251 ? 254 : $cmd == 253 ? 252 : undef;    # WILL->DONT, DO->WONT
            syswrite $self->{sock}, pack( 'C3', 255, $reply, $opt ) if defined $reply;
            next;
        }
        if ( $cmd == 250 ) {
            my $end = index $raw, "\xff\xf0";
            if ( $end < 0 ) { $self->{rawpend} = $raw; last }
            substr $raw, 0, $end + 2, '';
            next;
        }
        substr $raw, 0, 2, '';
    }
    $out =~ s/\r\n/\n/g;
    $out =~ s/\r\0/\r/g;
    print { $self->{ilog} } $out if $self->{ilog};
    $self->{buf} .= $out;
    return 1;
}

sub _compile {
    my ($p) = @_;
    my ( $body, $flags ) = $p =~ m{^\s*/(.*)/([msixpn]*)\s*$}s or return;
    my $re = eval "qr/\$body/$flags";
    return $re;
}

sub waitfor {
    my $self = shift;
    my @pats;
    my $timeout = $self->{timeout};
    if ( @_ == 1 ) { @pats = ( [ Match => $_[0] ] ) }
    else {
        while ( my ( $k, $v ) = splice @_, 0, 2 ) {
            if    ( $k =~ /^-?match$/i )   { push @pats, [ Match  => $v ] }
            elsif ( $k =~ /^-?string$/i )  { push @pats, [ String => $v ] }
            elsif ( $k =~ /^-?timeout$/i ) { $timeout = $v }
        }
    }
    my @res;
    for (@pats) {
        if ( $_->[0] eq 'Match' ) {
            my $re = _compile( $_->[1] ) or return $self->_err("bad match operator: $_->[1]");
            push @res, $re;
        }
        else { push @res, qr/\Q$_->[1]\E/ }
    }
    my $deadline = time + $timeout;
    while (1) {
        my ( $best, $bpos, $bend );
        for my $re (@res) {
            if ( $self->{buf} =~ $re ) {
                if ( !defined $bpos || $-[0] < $bpos ) { ( $bpos, $bend ) = ( $-[0], $+[0] ) }
            }
        }
        if ( defined $bpos ) {
            my $pre   = substr $self->{buf}, 0, $bpos;
            my $match = substr $self->{buf}, $bpos, $bend - $bpos;
            substr $self->{buf}, 0, $bend, '';
            return wantarray ? ( $pre, $match ) : 1;
        }
        return $self->_err('pattern match read eof') if $self->{eof};
        my $left = $deadline - time;
        return $self->_err('pattern match timed-out') if $left <= 0;
        $self->_fill( $left > 1 ? 1 : $left );
    }
}

sub cmd {
    my ( $self, @a ) = @_;
    my $string = @a == 1 ? $a[0] : {@a}->{String};
    $self->{errmsg} = '';
    $self->print($string) or return;
    my ($pre) = $self->waitfor( $self->{prompt} );
    return unless defined $pre;
    my @lines = $pre =~ /([^\n]*\n|[^\n]+$)/g;
    return wantarray ? @lines : 1;
}

sub close {
    my ($self) = @_;
    close $self->{sock} if $self->{sock};
    $self->{sock} = undef;
    return 1;
}

1;

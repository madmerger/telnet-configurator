package BSSim::CLI;
# Transport-independent CLI state machine for one simulated base station.
# feed() takes raw input bytes and returns the bytes the device would print.
use strict;
use warnings;
use BSSim::Profile;

use constant PAGE_LINES => 20;
use constant MORE       => ' --More-- ';

sub new {
    my ( $class, %a ) = @_;
    my $self = bless {
        profile         => BSSim::Profile->get( $a{profile} ),
        hostname        => $a{hostname} || 'BS-SIM',
        user            => $a{user}            // 'cbtadmin',
        password        => $a{password}        // 'cbt-pass',
        enable_password => $a{enable_password} // 'cbt-enable',
        preauth         => $a{preauth} ? 1 : 0,    # SSH: sshd already authenticated the user
        echo            => $a{echo}    ? 1 : 0,
        state           => 'init',
        line            => '',
        paging          => 1,
        privileged      => 0,
        failures        => 0,
        closed          => 0,
        skip_lf         => 0,
        pending         => [],
    }, $class;
    return $self;
}

sub closed { $_[0]{closed} }
sub set_echo { $_[0]{echo} = $_[1] ? 1 : 0 }

sub start {
    my ($self) = @_;
    my $p   = $self->{profile};
    my $out = "\r\n$p->{banner}\r\n";
    if ( $self->{preauth} ) {
        $self->{state} = 'cli';
        return $out . $self->_prompt;
    }
    $self->{state} = 'user';
    return $out . $p->{login_prompt};
}

sub _prompt {
    my ($self) = @_;
    my $p   = $self->{profile};
    my $fmt = $self->{privileged} && $p->{enable_prompt} ? $p->{enable_prompt} : $p->{user_prompt};
    return sprintf $fmt, $self->{hostname};
}

sub _crlf { my $t = shift; $t =~ s/\r?\n/\r\n/g; $t }

sub feed {
    my ( $self, $bytes ) = @_;
    my $out = '';
    for my $ch ( split //, $bytes ) {
        last if $self->{closed};
        if ( $self->{state} eq 'more' ) {
            if ( $self->{skip_lf} && ( $ch eq "\n" || $ch eq "\0" ) ) { $self->{skip_lf} = 0; next }
            $self->{skip_lf} = ( $ch eq "\r" || $ch eq ' ' || $ch eq 'q' ) ? 1 : 0;
            $out .= "\r" . ( ' ' x length MORE ) . "\r";
            if ( lc $ch eq 'q' ) {
                $self->{pending} = [];
                $self->{state}   = 'cli';
                $out .= $self->_prompt;
            }
            else {
                $out .= $self->_flush_page;
            }
            next;
        }
        if ( $self->{skip_lf} && ( $ch eq "\n" || $ch eq "\0" ) ) { $self->{skip_lf} = 0; next }
        $self->{skip_lf} = 0;
        if ( $ch eq "\r" || $ch eq "\n" ) {
            $self->{skip_lf} = 1 if $ch eq "\r";
            $out .= "\r\n" if $self->{echo};
            my $line = $self->{line};
            $self->{line} = '';
            $out .= $self->_line($line);
        }
        elsif ( $ch eq "\x7f" || $ch eq "\x08" ) {
            if ( length $self->{line} ) {
                chop $self->{line};
                $out .= "\x08 \x08" if $self->{echo} && !$self->_secret;
            }
        }
        elsif ( $ch eq "\x03" ) {    # Ctrl-C
            $self->{line} = '';
            $out .= "^C\r\n" . ( $self->{state} eq 'cli' ? $self->_prompt : '' );
        }
        elsif ( $ch eq "\x04" ) {    # Ctrl-D
            $self->{closed} = 1;
        }
        elsif ( ord $ch >= 32 ) {
            $self->{line} .= $ch;
            $out .= $ch if $self->{echo} && !$self->_secret;
        }
    }
    return $out;
}

sub _secret { my $s = $_[0]{state}; $s eq 'password' || $s eq 'enable_password' }

sub _line {
    my ( $self, $line ) = @_;
    my $p = $self->{profile};
    my $st = $self->{state};
    if ( $st eq 'user' ) {
        $self->{given_user} = $line;
        $self->{state}      = 'password';
        return $p->{password_prompt};
    }
    if ( $st eq 'password' ) {
        if ( $self->{given_user} eq $self->{user} && $line eq $self->{password} ) {
            $self->{state} = 'cli';
            return "\r\n" . $self->_prompt;
        }
        if ( ++$self->{failures} >= 3 ) {
            $self->{closed} = 1;
            return "\r\n% Authentication failed. Too many attempts.\r\n";
        }
        $self->{state} = 'user';
        return "\r\n% Authentication failed\r\n\r\n" . $p->{login_prompt};
    }
    if ( $st eq 'enable_password' ) {
        $self->{state} = 'cli';
        if ( $line eq $self->{enable_password} ) {
            $self->{privileged} = 1;
            return "\r\n" . $self->_prompt;
        }
        return "\r\n% Bad enable password\r\n" . $self->_prompt;
    }
    return $self->_command($line);
}

sub _command {
    my ( $self, $raw ) = @_;
    my $p   = $self->{profile};
    my $cmd = join ' ', split ' ', $raw;
    return $self->_prompt if $cmd eq '';

    if ( grep { $_ eq $cmd } @{ $p->{exit_cmds} } ) {
        if ( $self->{privileged} && $cmd eq 'exit' && $p->{enable_prompt} ) {
            $self->{privileged} = 0;
            return $self->_prompt;
        }
        $self->{closed} = 1;
        return '';
    }
    if ( $p->{enable_cmd} && $cmd eq $p->{enable_cmd} ) {
        return $self->_prompt if $self->{privileged};
        $self->{state} = 'enable_password';
        return 'Password: ';
    }
    if ( grep { $_ eq $cmd } @{ $p->{paging_cmds} } ) {
        $self->{paging} = 0;
        return $self->_prompt;
    }
    if ( !$self->{privileged} && grep { $_ eq $cmd } @{ $p->{privileged_cmds} } ) {
        return "% Command requires privileged mode (use '$p->{enable_cmd}')\r\n" . $self->_prompt;
    }
    my $text = BSSim::Profile->render( $p, $self->{hostname}, $cmd );
    if ( !defined $text ) {
        return "% Unknown command: \"$cmd\"\r\n" . $self->_prompt;
    }
    my @lines = map { "$_\r\n" } split /\n/, $text;
    return join( '', @lines ) . $self->_prompt unless $self->{paging};
    $self->{pending} = \@lines;
    return $self->_flush_page;
}

sub _flush_page {
    my ($self) = @_;
    my @page = splice @{ $self->{pending} }, 0, PAGE_LINES;
    my $out = join '', @page;
    if ( @{ $self->{pending} } ) {
        $self->{state} = 'more';
        return $out . MORE;
    }
    $self->{state} = 'cli';
    return $out . $self->_prompt;
}

1;

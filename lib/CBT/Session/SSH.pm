package CBT::Session::SSH;
# SSH session to a base station, driven through the system OpenSSH client (`ssh -tt`)
# so no extra CPAN modules are needed. sshd authenticates the user (password via
# SSH_ASKPASS, or public key), so the device CLI starts at its prompt: there is no
# login() step. The interface otherwise matches CBT::Session (enable / cmd / close).
use strict;
use warnings;
use Socket;
use IO::Select;
use POSIX ();
use File::Basename ();
use Cwd ();

our $SSH     = 'ssh';
our $ASKPASS = Cwd::abs_path( File::Basename::dirname(__FILE__) . '/../../../libexec/cbt-askpass' );

sub new {
    my ( $class, %a ) = @_;
    my $self = bless {
        %a,
        port    => $a{port} || 22,
        auth    => $a{auth} || 'password',
        timeout => $a{timeout} || 20,
        buf     => '',
        stderr  => '',
        secrets => [ grep { defined && length } $a{password} ],
    }, $class;
    $self->{prompt_re} = _re( $a{prompt} );
    if ( $a{log} ) {
        open $self->{logfh}, '>', $a{log} or die "cannot write session log $a{log}: $!\n";
        $self->{logfh}->autoflush(1);
    }
    $self->_spawn;
    my ( undef, $match ) = $self->waitfor( $self->{prompt_re} );
    die $self->_connect_error unless defined $match;
    return $self;
}

sub _re {
    my ($pat) = @_;
    return $pat if ref $pat eq 'Regexp';
    return qr/$1/ if $pat =~ m{^/(.*)/$}s;
    return qr/\Q$pat\E/;
}

sub _ssh_command {
    my ($self) = @_;
    my @o = (
        '-tt', '-e', 'none', '-x', '-a',
        '-p', $self->{port},
        '-l', $self->{user},
        '-o', "ConnectTimeout=$self->{timeout}",
        '-o', 'ClearAllForwardings=yes',
        '-o', 'LogLevel=ERROR',
        '-o', "StrictHostKeyChecking=$self->{host_key_check}",
        ( $self->{known_hosts} ? ( '-o', "UserKnownHostsFile=$self->{known_hosts}" ) : () ),
    );
    if ( $self->{auth} eq 'publickey' ) {
        die "ssh key file '$self->{key_file}' not found\n" unless defined $self->{key_file} && -r $self->{key_file};
        push @o, '-i', $self->{key_file}, '-o', 'IdentitiesOnly=yes', '-o', 'PreferredAuthentications=publickey',
          '-o', 'BatchMode=yes';
    }
    else {
        die "no password for $self->{user}\@$self->{host}\n" unless @{ $self->{secrets} };
        push @o, '-o', 'PreferredAuthentications=password,keyboard-interactive', '-o', 'PubkeyAuthentication=no',
          '-o', 'NumberOfPasswordPrompts=1', '-o', 'BatchMode=no';
    }
    return ( $SSH, @o, '--', $self->{host} );
}

sub _spawn {
    my ($self) = @_;
    $self->{host_key_check} ||= 'yes';
    my @cmd = $self->_ssh_command;
    socketpair( my $mine, my $theirs, AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or die "socketpair: $!\n";
    pipe( my $err_r, my $err_w ) or die "pipe: $!\n";
    defined( my $pid = fork ) or die "fork: $!\n";
    if ( !$pid ) {
        CORE::close $mine;
        CORE::close $err_r;
        POSIX::setsid();    # no controlling tty: ssh must use SSH_ASKPASS, never prompt on a terminal
        open STDIN,  '<&', $theirs or POSIX::_exit(127);
        open STDOUT, '>&', $theirs or POSIX::_exit(127);
        open STDERR, '>&', $err_w  or POSIX::_exit(127);
        if ( $self->{auth} eq 'password' ) {
            @ENV{qw(SSH_ASKPASS SSH_ASKPASS_REQUIRE CBT_SSH_ASKPASS_SECRET)} = ( $ASKPASS, 'force', $self->{password} );
            $ENV{DISPLAY} //= 'none';
        }
        else {
            $ENV{SSH_ASKPASS_REQUIRE} = 'never';
            delete $ENV{CBT_SSH_ASKPASS_SECRET};
        }
        exec {$cmd[0]} @cmd or POSIX::_exit(127);
    }
    CORE::close $theirs;
    CORE::close $err_w;
    $self->{pid} = $pid;
    @{$self}{qw(fh errfh)} = ( $mine, $err_r );
}

# waitfor(qr/a/, qr/b/, ...) -> (text before the match, matched text, index of the pattern); () on timeout/EOF.
sub waitfor {
    my ( $self, @res ) = @_;
    @res = map { _re($_) } @res;
    my $deadline = time + $self->{timeout};
    while (1) {
        for my $i ( 0 .. $#res ) {
            if ( $self->{buf} =~ $res[$i] ) {
                my ( $pre, $match ) = ( substr( $self->{buf}, 0, $-[0] ), $& );
                substr( $self->{buf}, 0, $+[0] ) = '';
                return ( $pre, $match, $i );
            }
        }
        my $left = $deadline - time;
        if ( $left <= 0 ) { $self->{errmsg} = 'timed out waiting for the device'; return }
        return unless $self->_read($left);
    }
}

sub _read {
    my ( $self, $wait ) = @_;
    my $sel = IO::Select->new( grep { defined } @{$self}{qw(fh errfh)} );
    for my $fh ( $sel->can_read($wait) ) {
        my $n = sysread $fh, my $data, 65536;
        if ( $fh == $self->{errfh} ) {
            if   ($n) { $self->{stderr} .= $data }
            else      { CORE::close $fh; $self->{errfh} = undef }
            next;
        }
        if ( !$n ) { $self->{errmsg} = 'connection closed'; $self->{eof} = 1; return 0 }
        $self->_log($data);
        $self->{buf} .= $data;
    }
    return 1;
}

sub _log {
    my ( $self, $data ) = @_;
    return unless $self->{logfh};
    $data =~ s/\Q$_\E/********/g for @{ $self->{secrets} };
    print { $self->{logfh} } $data;
}

sub _send {
    my ( $self, $text ) = @_;
    defined syswrite( $self->{fh}, $text ) or die "ssh write failed: $!\n";
}

sub _connect_error {
    my ($self) = @_;
    $self->_reap(5);
    1 while $self->{errfh} && $self->_read(1) && $self->{errfh};
    ( my $err = $self->{stderr} ) =~ s/\r//g;
    $err = join '; ', grep { /\S/ } split /\n/, $err;
    my $where = "$self->{user}\@$self->{host}:$self->{port}";
    return "login failed for $self->{user} (ssh: $err)\n" if $err =~ /Permission denied/;
    return "ssh connect to $where failed: " . ( $err || $self->{errmsg} || 'no prompt' ) . "\n";
}

sub login { 1 }    # authentication is done by sshd

sub enable {
    my ( $self, $cmd, $password ) = @_;
    push @{ $self->{secrets} }, $password if defined $password && length $password;
    $self->_send("$cmd\n");
    my @got = $self->waitfor('/Password: ?$/');
    die "no enable password prompt\n" unless @got;
    $self->_send("$password\n");
    my ( undef, $match, $i ) = $self->waitfor( $self->{prompt_re}, '/% Bad enable password/' );
    die "enable failed\n" if !defined $match || $i == 1;
    return 1;
}

sub cmd {
    my ( $self, $cmd ) = @_;
    $self->_send("$cmd\n");
    my ( $out, $match ) = $self->waitfor( $self->{prompt_re} );
    die "command '$cmd' failed: $self->{errmsg}\n" unless defined $match;
    $out =~ s/\r//g;
    $out =~ s/^\Q$cmd\E\n//;    # the remote pty echoes what we type
    return $out;
}

sub close {
    my ( $self, $exit_cmd ) = @_;
    eval { $self->_send( ( $exit_cmd || 'exit' ) . "\n" ) } unless $self->{eof};
    # Like the Telnet session: send the exit command, then hang up (some CLIs need two exits).
    $self->_read(0.5) unless $self->{eof};
    $self->_reap(1);
}

sub _reap {
    my ( $self, $secs ) = @_;
    return unless $self->{pid};
    if ( $self->{fh} ) { CORE::close $self->{fh}; $self->{fh} = undef }
    for ( 1 .. $secs * 10 ) {
        if ( waitpid( $self->{pid}, POSIX::WNOHANG() ) ) { $self->{pid} = undef; return }
        select undef, undef, undef, 0.1;
    }
    kill 'TERM', $self->{pid};
    waitpid $self->{pid}, 0;
    $self->{pid} = undef;
}

sub DESTROY {
    my ($self) = @_;
    local ( $?, $@ );
    $self->_reap(0) if $self->{pid};
    CORE::close $self->{logfh} if $self->{logfh};
}

1;

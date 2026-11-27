package CBT::SSH;
# SSH transport. Net::OpenSSH connects and authenticates (password or public key),
# then the remote shell's pseudo-terminal is wrapped in a Net::Telnet object
# (Telnetmode off) so prompt matching, cmd() and waitfor() work as over Telnet.
# sshd has already authenticated the user: there is no login/password prompt.
use strict;
use warnings;
use Net::OpenSSH;
use Net::Telnet;
use File::Temp qw(tempfile);
use POSIX qw(WNOHANG);

my %HOST_KEY_CHECK = map { $_ => 1 } qw(yes no accept-new);

# host port user auth(password|key) password key_file host_key_check known_hosts
# timeout prompt log errmode
sub open {
    my ( $class, %a ) = @_;
    my $port    = $a{port}    || 22;
    my $timeout = $a{timeout} || 20;
    my $auth    = $a{auth}    || 'password';
    my $hkc     = $a{host_key_check} || 'yes';
    my $where   = "$a{host}:$port";
    die "unknown host_key_check '$hkc' (yes|no|accept-new)\n" unless $HOST_KEY_CHECK{$hkc};

    my @opts = ( -o => "StrictHostKeyChecking=$hkc", -o => "ConnectTimeout=$timeout", -o => 'LogLevel=ERROR' );
    if ( $hkc eq 'yes' ) {    # only host keys registered in advance are trusted
        die "host_key_check = yes but known_hosts is empty (environment variable not set?)\n"
          unless length( $a{known_hosts} // '' );
        die "known_hosts file '$a{known_hosts}' is not readable\n" unless -r $a{known_hosts};
    }
    if    ( $hkc eq 'no' )   { push @opts, -o => 'UserKnownHostsFile=/dev/null' }
    elsif ( $a{known_hosts} ) {    # trust only this file, not /etc/ssh/ssh_known_hosts
        push @opts, -o => "UserKnownHostsFile=$a{known_hosts}", -o => 'GlobalKnownHostsFile=/dev/null';
    }

    my %cred;
    if ( $auth eq 'key' ) {
        die "ssh auth = key but key_file is empty (environment variable not set?)\n" unless length( $a{key_file} // '' );
        die "ssh key file '$a{key_file}' is not readable\n" unless -r $a{key_file};
        %cred = ( key_path => $a{key_file} );
        push @opts, -o => 'PreferredAuthentications=publickey', -o => 'IdentitiesOnly=yes', -o => 'BatchMode=yes';
    }
    elsif ( $auth eq 'password' ) {
        die "ssh auth = password but password is empty (environment variable not set?)\n"
          unless length( $a{password} // '' );
        %cred = ( password => $a{password} );
        push @opts, -o => 'PubkeyAuthentication=no';
    }
    else {
        die "unknown auth '$auth' (password|key)\n";
    }

    my $errfh = tempfile();
    my $ssh   = Net::OpenSSH->new(
        $a{host},
        port                => $port,
        user                => $a{user},
        timeout             => $timeout,
        kill_ssh_on_timeout => 1,
        master_stderr_fh    => $errfh,
        master_opts         => \@opts,
        %cred,
    );
    if ( $ssh->error ) {
        seek $errfh, 0, 0;
        my $detail = join ' ', grep { /\S/ } map { s/\s+$//r } <$errfh>;
        die "ssh login to $where failed ($auth auth): " . $ssh->error . ( length $detail ? " [$detail]" : '' ) . "\n";
    }

    my ( $pty, $pid ) = $ssh->open2pty( { tty => 1 } )
      or die "ssh shell on $where failed: " . $ssh->error . "\n";

    my $t = Net::Telnet->new(
        Fhopen                  => $pty,
        Telnetmode              => 0,        # raw SSH channel, no Telnet option negotiation
        Binmode                 => 1,        # no CR/LF translation; the remote pty maps LF itself
        Output_record_separator => "\n",
        Cmd_remove_mode         => 1,        # the remote pty echoes each command line
        Timeout                 => $timeout,
        Errmode                 => $a{errmode} || 'die',
        ( defined $a{prompt} ? ( Prompt    => $a{prompt} ) : () ),
        ( $a{log}            ? ( Input_log => $a{log} )    : () ),
    );
    return bless { ssh => $ssh, pid => $pid, t => $t }, $class;
}

sub telnet { $_[0]{t} }

# Idempotent; also runs from DESTROY so the ssh child is reaped when collection dies midway.
sub close {
    my ($self) = @_;
    my $pid = delete $self->{pid} or return 1;
    $self->{t}->close;    # closing the pty master hangs up the ssh client
    for ( 1 .. 20 ) {
        return $self->_done if waitpid( $pid, WNOHANG ) != 0;
        select undef, undef, undef, 0.1;
    }
    kill 'TERM', $pid;
    waitpid $pid, 0;
    $self->_done;
}

sub _done { my ($self) = @_; undef $self->{ssh}; 1 }

sub DESTROY {
    my ($self) = @_;
    local ( $@, $!, $? );
    $self->close;
}

1;

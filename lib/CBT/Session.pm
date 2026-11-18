package CBT::Session;
# Session to a base station over Telnet or SSH: login, privileged mode, command execution.
#
# SSH: Net::OpenSSH authenticates (password or public key) and opens a pseudo
# terminal; the device CLI on it is driven with the same Net::Telnet prompt
# handling as Telnet. sshd has already authenticated the user, so there is no
# device login dialogue (see preauthenticated / wait_prompt).
use strict;
use warnings;
use Net::Telnet;
use File::Temp ();

my %HOST_KEY_CHECK = ( yes => 'yes', 'accept-new' => 'accept-new' );

sub new {
    my ( $class, %a ) = @_;
    $a{protocol} ||= 'telnet';
    my $self = bless {%a}, $class;
    if    ( $a{protocol} eq 'telnet' ) { $self->_open_telnet }
    elsif ( $a{protocol} eq 'ssh' )    { $self->_open_ssh }
    else                               { die "unknown protocol '$a{protocol}' (telnet|ssh)\n" }
    return $self;
}

sub _net_telnet_opts {
    my ($self) = @_;
    return (
        Timeout => $self->{timeout} || 20,
        Errmode => 'return',
        Prompt  => $self->{prompt},
        ( $self->{log} ? ( Input_log => $self->{log} ) : () ),
    );
}

sub _open_telnet {
    my ($self) = @_;
    my $port = $self->{port} || 23;
    my $t    = Net::Telnet->new( $self->_net_telnet_opts );
    $t->open( Host => $self->{host}, Port => $port )
      or die "telnet connect to $self->{host}:$port failed: " . $t->errmsg . "\n";
    $self->{t} = $t;
}

sub _open_ssh {
    my ($self) = @_;
    require Net::OpenSSH;
    my $port  = $self->{port} || 22;
    my $auth  = $self->{auth} || 'password';
    my $check = $HOST_KEY_CHECK{ $self->{host_key_check} || 'yes' }
      or die "host_key_check must be yes or accept-new\n";
    my @opts = (
        -o => "StrictHostKeyChecking=$check",
        -o => 'LogLevel=ERROR',
        ( $self->{known_hosts} ? ( -o => "UserKnownHostsFile=$self->{known_hosts}" ) : () ),
    );
    my %auth;
    if ( $auth eq 'key' ) {
        die "auth = key needs key_file\n" unless $self->{key_file};
        die "key_file $self->{key_file} not readable\n" unless -r $self->{key_file};
        %auth = (
            key_path => $self->{key_file},
            ( defined $self->{key_passphrase} && length $self->{key_passphrase} ? ( passphrase => $self->{key_passphrase} ) : () ),
        );
        push @opts, -o => 'IdentitiesOnly=yes', -o => 'PreferredAuthentications=publickey';
    }
    elsif ( $auth eq 'password' ) {
        die "auth = password needs a password\n" unless defined $self->{password} && length $self->{password};
        %auth = ( password => $self->{password} );
        push @opts, -o => 'PubkeyAuthentication=no', -o => 'PreferredAuthentications=password,keyboard-interactive';
    }
    else { die "unknown auth '$auth' (password|key)\n" }

    my $stderr = File::Temp->new;    # ssh's own diagnostics, e.g. "Permission denied"
    my $ssh    = Net::OpenSSH->new(
        $self->{host},
        port             => $port,
        user             => $self->{user},
        timeout          => $self->{timeout} || 20,
        master_opts      => \@opts,
        master_stderr_fh => $stderr,
        %auth,
    );
    if ( $ssh->error ) {
        my $why = do { local $/; open my $fh, '<', $stderr->filename; my $t = <$fh> // ''; ( grep {/\S/} split /\r?\n/, $t )[-1] };
        ( my $err = $ssh->error ) =~ s/\s+$//;
        die "ssh connect to $self->{host}:$port ($auth auth) failed: " . ( $why // $err ) . "\n";
    }
    my ( $pty, $pid ) = $ssh->open2pty
      or die "ssh session to $self->{host}:$port failed: " . $ssh->error . "\n";
    my $t = Net::Telnet->new(
        $self->_net_telnet_opts,
        Fhopen                  => $pty,
        Telnetmode              => 0,     # a pty carries no Telnet option negotiation
        Cmd_remove_mode         => 1,     # the device CLI echoes the command line
        Output_record_separator => "\r",
    );
    @{$self}{qw(ssh pty pid t)} = ( $ssh, $pty, $pid, $t );
}

# True when the transport already authenticated the user (SSH), so the
# device's own Username:/login: and Password: prompts never appear.
sub preauthenticated { $_[0]{protocol} eq 'ssh' }

sub wait_prompt {
    my ($self) = @_;
    my $t = $self->{t};
    $t->waitfor( $t->prompt ) or die "no CLI prompt: " . $t->errmsg . "\n";
    return 1;
}

sub login {
    my ( $self, $user, $password ) = @_;
    my $t = $self->{t};
    $t->waitfor( $self->{login_prompt} )    or die "no login prompt: " . $t->errmsg . "\n";
    $t->print($user);
    $t->waitfor( $self->{password_prompt} ) or die "no password prompt: " . $t->errmsg . "\n";
    $t->print($password);
    my ( $pre, $match ) = $t->waitfor( Match => $t->prompt, Match => '/% Authentication failed/' );
    die "login failed for $user\n" if !defined $match || $match =~ /Authentication failed/;
    return 1;
}

sub enable {
    my ( $self, $cmd, $password ) = @_;
    my $t = $self->{t};
    $t->print($cmd);
    $t->waitfor('/Password: ?$/') or die "no enable password prompt\n";
    $t->print($password);
    my ( $pre, $match ) = $t->waitfor( Match => $t->prompt, Match => '/% Bad enable password/' );
    # The device prints its prompt again after the error, so look at everything before it too.
    die "enable failed\n" if !defined $match || "$pre$match" =~ /Bad enable/;
    return 1;
}

sub cmd {
    my ( $self, $cmd ) = @_;
    my @lines = $self->{t}->cmd($cmd);
    die "command '$cmd' failed: " . $self->{t}->errmsg . "\n" if !@lines && $self->{t}->errmsg;
    s/\r//g for @lines;
    return join '', @lines;
}

sub close {
    my ( $self, $exit_cmd ) = @_;
    $self->{t}->print( $exit_cmd || 'exit' );
    $self->{t}->close;
    waitpid $self->{pid}, 0 if $self->{pid};
    delete $self->{ssh};    # stops the ssh master connection
}

1;

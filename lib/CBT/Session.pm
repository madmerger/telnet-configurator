package CBT::Session;
# Session to a base station over Telnet or SSH: login, privileged mode, command execution.
#
# SSH: Net::OpenSSH authenticates (password or key) and opens a PTY; the device CLI
# on that PTY is then driven with the same Net::Telnet prompt handling as Telnet.
use strict;
use warnings;
use Net::Telnet;

sub new {
    my ( $class, %a ) = @_;
    $a{protocol} ||= 'telnet';
    my $self = bless {%a}, $class;
    if    ( $a{protocol} eq 'telnet' ) { $self->_open_telnet }
    elsif ( $a{protocol} eq 'ssh' )    { $self->_open_ssh }
    else                               { die "unknown protocol '$a{protocol}' (telnet|ssh)\n" }
    return $self;
}

sub _open_telnet {
    my ($self) = @_;
    my $port = $self->{port} || 23;
    my $t = Net::Telnet->new( $self->_telnet_opts );
    $t->open( Host => $self->{host}, Port => $port )
      or die "telnet connect to $self->{host}:$port failed: " . $t->errmsg . "\n";
    $self->{t} = $t;
}

sub _open_ssh {
    my ($self) = @_;
    require Net::OpenSSH;
    my $port = $self->{port} || 22;
    my $auth = $self->{auth} || ( $self->{key_file} ? 'key' : 'password' );
    my @known_hosts = $self->{known_hosts}
      ? ( -o => "UserKnownHostsFile=$self->{known_hosts}", -o => 'StrictHostKeyChecking=accept-new', -o => 'LogLevel=ERROR' )
      : ();
    my $ssh = Net::OpenSSH->new(
        $self->{host},
        port    => $port,
        user    => $self->{user},
        timeout => $self->{timeout} || 20,
        ( $auth eq 'key'
            ? ( key_path => $self->{key_file}, master_opts => [ @known_hosts, -o => 'PasswordAuthentication=no' ] )
            : ( password => $self->{password}, master_opts => [ @known_hosts, -o => 'PubkeyAuthentication=no' ] ) ),
    );
    die "ssh connect to $self->{host}:$port ($auth auth) failed: " . $ssh->error . "\n" if $ssh->error;
    my ( $pty, $pid ) = $ssh->open2pty
      or die "ssh session to $self->{host}:$port failed: " . $ssh->error . "\n";
    my $t = Net::Telnet->new(
        $self->_telnet_opts,
        Fhopen                  => $pty,
        Telnetmode              => 0,
        Binmode                 => 1,
        Output_record_separator => "\r", Cmd_remove_mode => 1,
    );
    @{$self}{qw(ssh pty pid t)} = ( $ssh, $pty, $pid, $t );
}

sub _telnet_opts {
    my ($self) = @_;
    return (
        Timeout => $self->{timeout} || 20,
        Errmode => 'return',
        Prompt  => $self->{prompt},
        ( $self->{log} ? ( Input_log => $self->{log} ) : () ),
    );
}

# Telnet: answer the device's login prompts. SSH: sshd already authenticated us,
# so just wait for the CLI prompt.
sub login {
    my ( $self, $user, $password ) = @_;
    my $t = $self->{t};
    if ( $self->{protocol} eq 'ssh' ) {
        $t->waitfor( $t->prompt ) or die "no CLI prompt after ssh login: " . $t->errmsg . "\n";
        return 1;
    }
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
    die "enable failed\n" if !defined $match || $match =~ /Bad enable/;
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
    if ( $self->{pid} ) { waitpid $self->{pid}, 0 }
    delete $self->{ssh};
}

1;

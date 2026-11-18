package CBT::Session;
# Session to a base station over Telnet or SSH: login, privileged mode, command execution.
# Both protocols drive a Net::Telnet object (over SSH it wraps the remote pty, see CBT::SSH),
# so prompts, pager handling and enable work the same way.
use strict;
use warnings;
use Net::Telnet;

sub new {
    my ( $class, %a ) = @_;
    my $proto = $a{protocol} || 'telnet';
    my ( $t, $ssh );
    if ( $proto eq 'ssh' ) {
        require CBT::SSH;
        $ssh = CBT::SSH->open( %a, errmode => 'return' );
        $t   = $ssh->telnet;
    }
    elsif ( $proto eq 'telnet' ) {
        $t = Net::Telnet->new(
            Timeout => $a{timeout} || 20,
            Errmode => 'return',
            Prompt  => $a{prompt},
            ( $a{log} ? ( Input_log => $a{log} ) : () ),
        );
        $t->open( Host => $a{host}, Port => $a{port} || 23 )
          or die "telnet connect to $a{host}:@{[ $a{port} || 23 ]} failed: " . $t->errmsg . "\n";
    }
    else {
        die "unknown protocol '$proto'\n";
    }
    delete @a{qw(password key_file)};
    return bless { t => $t, ssh => $ssh, %a }, $class;
}

sub login {
    my ( $self, $user, $password ) = @_;
    my $t = $self->{t};
    if ( $self->{ssh} ) {    # sshd already authenticated the user
        $t->waitfor( $t->prompt ) or die "no prompt after ssh login: " . $t->errmsg . "\n";
        return 1;
    }
    $t->waitfor( $self->{login_prompt} )    or die "no login prompt: " . $t->errmsg . "\n";
    $t->print($user);
    $t->waitfor( $self->{password_prompt} ) or die "no password prompt: " . $t->errmsg . "\n";
    $t->print($password);
    my ( $pre, $match ) = $t->waitfor( Match => '/% Authentication failed/', Match => $t->prompt );
    die "login failed for $user\n" if !defined $match || $match =~ /Authentication failed/;
    return 1;
}

sub enable {
    my ( $self, $cmd, $password ) = @_;
    my $t = $self->{t};
    $t->print($cmd);
    $t->waitfor('/Password: ?$/') or die "no enable password prompt\n";
    # Over SSH the remote pty may echo the password; keep it out of the session log.
    my $log = $self->{ssh} ? $t->input_log('') : undef;
    $t->print($password);
    my ( $pre, $match ) = $t->waitfor( Match => '/% Bad enable password/', Match => $t->prompt );
    $t->input_log($log) if $log;
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
    $self->{ssh} ? $self->{ssh}->close : $self->{t}->close;
}

1;

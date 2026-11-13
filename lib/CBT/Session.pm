package CBT::Session;
# Telnet session to a base station: login, privileged mode, command execution.
use strict;
use warnings;
use Net::Telnet;

sub new {
    my ( $class, %a ) = @_;
    my $t = Net::Telnet->new(
        Timeout => $a{timeout} || 20,
        Errmode => 'return',
        Prompt  => $a{prompt},
        ( $a{log} ? ( Input_log => $a{log} ) : () ),
    );
    $t->open( Host => $a{host}, Port => $a{port} || 23 )
      or die "telnet connect to $a{host}:@{[ $a{port} || 23 ]} failed: " . $t->errmsg . "\n";
    return bless { t => $t, %a }, $class;
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
}

1;

package CBT::Collector::Base;
# Common collection flow; per model/software subclasses override the settings.
use strict;
use warnings;
use CBT::Session;

sub new { my ( $class, %a ) = @_; bless {%a}, $class }

sub prompt          { die 'subclass must define prompt' }
sub login_prompt    { '/Username: ?$/' }
sub password_prompt { '/Password: ?$/' }
sub enable_cmd      { undef }
sub paging_cmd      { die 'subclass must define paging_cmd' }
sub commands        { die 'subclass must define commands' }
sub exit_cmd        { 'exit' }

# Device inventory keys that select and authenticate the transport.
sub session_args {
    my ( $class, $dev ) = @_;
    return map { defined $dev->{$_} ? ( $_ => $dev->{$_} ) : () }
      qw(host port protocol user password auth key_file key_passphrase known_hosts host_key_check);
}

sub collect {
    my ( $self, $dev ) = @_;
    my $step = $self->{progress} || sub { };
    my $s = CBT::Session->new(
        $self->session_args($dev),
        timeout         => $self->{timeout},
        log             => $self->{session_log},
        prompt          => $self->prompt,
        login_prompt    => $self->login_prompt,
        password_prompt => $self->password_prompt,
    );
    if ( $s->preauthenticated ) {
        $step->("ssh authenticated ($dev->{auth})");
        $s->wait_prompt;
    }
    else {
        $step->('telnet login');
        $s->login( $dev->{user}, $dev->{password} );
    }
    if ( $self->enable_cmd ) {
        $step->( $self->enable_cmd );
        $s->enable( $self->enable_cmd, $dev->{enable_password} );
    }
    $step->( $self->paging_cmd );
    $s->cmd( $self->paging_cmd );
    my @sections = map { $step->($_); [ $_, $s->cmd($_) ] } $self->commands;
    $s->close( $self->exit_cmd );
    return \@sections;
}

1;

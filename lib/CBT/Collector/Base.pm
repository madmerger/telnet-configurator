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

sub collect {
    my ( $self, $dev ) = @_;
    my $s = CBT::Session->new(
        host            => $dev->{host},
        port            => $dev->{port},
        timeout         => $self->{timeout},
        log             => $self->{session_log},
        prompt          => $self->prompt,
        login_prompt    => $self->login_prompt,
        password_prompt => $self->password_prompt,
    );
    $s->login( $dev->{user}, $dev->{password} );
    $s->enable( $self->enable_cmd, $dev->{enable_password} ) if $self->enable_cmd;
    $s->cmd( $self->paging_cmd );
    my @sections = map { [ $_, $s->cmd($_) ] } $self->commands;
    $s->close( $self->exit_cmd );
    return \@sections;
}

1;

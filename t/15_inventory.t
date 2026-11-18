use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use CBT::Inventory;
use TestLab qw(write_inventory);

delete @ENV{qw(CBT_PASSWORD CBT_ENABLE_PASSWORD CBT_SSH_KEY_FILE CBT_SSH_KNOWN_HOSTS CBT_SSH_HOST_KEY_CHECK)};
my %base = ( host => '127.0.0.1', model => 'AX-4000', sw => 'R5.2.1', user => 'cbtadmin' );

sub load_one { CBT::Inventory->load( write_inventory( { name => 'D1', %base, @_ } ) )->[0] }
sub load_err { eval { load_one(@_) }; $@ }

subtest 'telnet stays the default' => sub {
    my $d = load_one( password => 'p' );
    is $d->{protocol}, 'telnet', 'protocol';
    is $d->{port},     23,       'port';
    ok !exists $d->{auth}, 'no ssh settings';
};

subtest 'ssh defaults' => sub {
    my $d = load_one( protocol => 'SSH', password => 'p' );
    is $d->{protocol},       'ssh',      'protocol (case-insensitive)';
    is $d->{port},           22,         'port';
    is $d->{auth},           'password', 'password auth without a key';
    is $d->{host_key_check}, 'yes',      'strict host key checking';
    is load_one( protocol => 'ssh', key_file => '/k', port => 2201 )->{auth}, 'publickey', 'publickey when a key is set';
    is load_one( protocol => 'ssh', key_file => '~/k' )->{key_file}, "$ENV{HOME}/k", '~ expanded';
};

subtest 'secrets from the environment' => sub {
    local $ENV{CBT_PASSWORD}        = 'env-pass';
    local $ENV{CBT_ENABLE_PASSWORD} = 'env-enable';
    local $ENV{CBT_SSH_KEY_FILE}    = '/env/key';
    local $ENV{MY_PASS}             = 'ref-pass';
    my $d = load_one( protocol => 'ssh', auth => 'password' );
    is $d->{password},        'env-pass',   'password fallback';
    is $d->{enable_password}, 'env-enable', 'enable_password fallback';
    is load_one( protocol => 'ssh', auth => 'publickey' )->{key_file}, '/env/key', 'key_file fallback';
    is load_one( password => '${MY_PASS}' )->{password}, 'ref-pass', '${NAME} reference wins';
    is load_one( password => '${UNSET_CBT_VAR}' )->{password}, 'env-pass', 'unset reference falls back';
    is load_one( password => 'inline' )->{password}, 'inline', 'inline value wins';
};

subtest 'invalid settings are rejected' => sub {
    like load_err( protocol => 'rlogin' ), qr/unknown protocol 'rlogin'/, 'protocol';
    like load_err( protocol => 'ssh', auth => 'kerberos' ), qr/unknown auth 'kerberos'/, 'auth';
    like load_err( protocol => 'ssh', auth => 'publickey' ), qr/needs 'key_file'/, 'publickey without key';
    like load_err( protocol => 'ssh', user => '${UNSET_CBT_VAR}' ), qr/ssh needs 'user'/, 'ssh without user';
    like load_err( protocol => 'ssh', host_key_check => 'maybe' ), qr/host_key_check must be/, 'host_key_check';
};

done_testing;

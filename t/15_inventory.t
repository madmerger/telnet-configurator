use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use TestLab qw(write_inventory);
use CBT::Inventory;

my %base = ( name => 'D1', host => '127.0.0.1', model => 'AX-4000', sw => 'R5.2.1', user => 'cbtadmin' );
sub load_one { CBT::Inventory->load( write_inventory( {@_} ) )->[0] }
sub load_err { eval { load_one(@_) }; $@ }

subtest 'defaults keep existing Telnet inventories working' => sub {
    my $d = load_one( %base, password => 'x' );
    is $d->{protocol}, 'telnet', 'protocol defaults to telnet';
    is $d->{port},     23,       'telnet port defaults to 23';
};

subtest 'ssh defaults' => sub {
    my $d = load_one( %base, protocol => 'ssh', password => 'x' );
    is $d->{port},           22,         'ssh port defaults to 22';
    is $d->{auth},           'password', 'auth defaults to password';
    is $d->{host_key_check}, 'yes',      'host keys are checked strictly by default';
    $d = load_one( %base, protocol => 'ssh', auth => 'key', key_file => '/k', port => 2201, host_key_check => 'accept-new' );
    is_deeply [ @{$d}{qw(auth key_file port host_key_check)} ], [ 'key', '/k', 2201, 'accept-new' ], 'explicit values kept';
};

subtest 'secrets from ${NAME} environment references' => sub {
    local $ENV{T_CBT_PW}  = 'from-env';
    local $ENV{T_CBT_KEY} = '/keys/id';
    my $d = load_one( %base, protocol => 'ssh', password => '${T_CBT_PW}' );
    is $d->{password}, 'from-env', 'password';
    $d = load_one( %base, protocol => 'ssh', auth => 'key', key_file => '${T_CBT_KEY}' );
    is $d->{key_file}, '/keys/id', 'key_file';
    delete $ENV{T_CBT_PW};
    like load_err( %base, protocol => 'ssh', password => '${T_CBT_PW}' ), qr/auth = password needs password/,
      'unset variable is reported for password auth';
};

subtest 'invalid settings are rejected' => sub {
    like load_err( %base, protocol => 'rsh' ), qr/protocol must be telnet or ssh/, 'protocol';
    like load_err( %base, protocol => 'ssh', auth => 'otp' ), qr/auth must be password or key/, 'auth';
    like load_err( %base, protocol => 'ssh', auth => 'key' ), qr/auth = key needs key_file/, 'key_file required';
    like load_err( %base, protocol => 'ssh', password => 'x', host_key_check => 'no' ), qr/host_key_check must be/,
      'host key checking cannot be turned off';
    like load_err( %base, auth => 'key', key_file => '/k' ), qr/'auth' needs protocol = ssh/, 'ssh keys on a telnet device';
};

done_testing;

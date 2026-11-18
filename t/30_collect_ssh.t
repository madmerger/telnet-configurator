# SSH collection against the README labs (started separately):
#   make lab-ssh-start      lab/ssh,    public key,           127.0.0.1:2201-2203, user $USER
#   make lab-docker-start   lab/docker, password + public key, 127.0.0.1:2401-2403, user cbtadmin
# A lab that is not running is skipped. With Net::Telnet installed, the SSH results are
# also compared with a Telnet collection of the same devices (before/after the migration).
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/lib";
use TestLab qw(root start_telnet_sim write_inventory run_collect expected_sections parse_sections port_open have_net_telnet);

delete @ENV{qw(CBT_PASSWORD CBT_ENABLE_PASSWORD CBT_SSH_KEY_FILE CBT_SSH_KNOWN_HOSTS CBT_SSH_HOST_KEY_CHECK)};

# Device names must match the lab hostnames: the simulator prints them in the config.
my @DEVICES = (
    [ 'TKY-ENB-0001', 'ax4000-r5', 'AX-4000', 'R5.2.1',      1 ],
    [ 'OSK-ENB-0102', 'ax4000-r6', 'AX-4000', 'R6.1.0',      2 ],
    [ 'NGY-GNB-0203', 'bg7-v200',  'BG-7',    'V200R003C10', 3 ],
);
my $KEY  = root() . '/lab/.state/cbt_id_ed25519';
my $TMP  = tempdir( CLEANUP => 1 );
my $KH   = "$TMP/known_hosts";
my $USER = getpwuid($<) // $ENV{USER};

my %LAB = (
    'lab/ssh'    => { base => 2200, user => $USER },
    'lab/docker' => { base => 2400, user => 'cbtadmin' },
);

sub lab_ready {
    my ($lab) = @_;
    return 0 unless -r $KEY;
    return !grep { !port_open( $LAB{$lab}{base} + $_->[4] ) } @DEVICES;
}

# inventory entries for a lab; %over is applied to every device (undef deletes a key)
sub ssh_devices {
    my ( $lab, %over ) = @_;
    return map {
        my %d = (
            name            => $_->[0],
            protocol        => 'ssh',
            host            => '127.0.0.1',
            port            => $LAB{$lab}{base} + $_->[4],
            model           => $_->[2],
            sw              => $_->[3],
            user            => $LAB{$lab}{user},
            enable_password => 'cbt-enable',
            host_key_check  => 'accept-new',
            known_hosts     => $KH,
            %over,
        );
        delete $d{$_} for grep { !defined $d{$_} } keys %d;
        \%d;
    } @DEVICES;
}

sub collect_ok {
    my ( $label, @devs ) = @_;
    my ( $rc, $stdout, $outdir, $logdir ) = run_collect( write_inventory(@devs) );
    is $rc, 0, "$label: all devices collected" or diag $stdout;
    my %got;
    for my $dev (@DEVICES) {
        my ( $name, $profile ) = @$dev;
        my $file = "$outdir/$name/latest.cfg";
        ok -s $file, "$label: $name output written" or next;
        $got{$name} = parse_sections($file);
        is_deeply $got{$name}, expected_sections( $profile, $name ), "$label: $name matches the device";
    }
    my $logs = join '', map { local ( @ARGV, $/ ) = $_; <> } glob "$logdir/*.session.log";
    unlike $logs, qr/cbt-pass|cbt-enable/, "$label: no secrets in the session logs";
    return \%got;
}

my %collected;

subtest 'lab/ssh: public key' => sub {
    plan skip_all => 'lab/ssh is not running (make lab-ssh-start)' unless lab_ready('lab/ssh');
    $collected{'ssh publickey (lab/ssh)'} =
      collect_ok( 'lab/ssh publickey', ssh_devices( 'lab/ssh', auth => 'publickey', key_file => $KEY ) );
};

subtest 'lab/docker: password' => sub {
    plan skip_all => 'lab/docker is not running (make lab-docker-start)' unless lab_ready('lab/docker');
    $collected{'ssh password (lab/docker)'} =
      collect_ok( 'lab/docker password', ssh_devices( 'lab/docker', auth => 'password', password => 'cbt-pass' ) );
};

subtest 'lab/docker: public key' => sub {
    plan skip_all => 'lab/docker is not running (make lab-docker-start)' unless lab_ready('lab/docker');
    $collected{'ssh publickey (lab/docker)'} =
      collect_ok( 'lab/docker publickey', ssh_devices( 'lab/docker', auth => 'publickey', key_file => $KEY ) );
};

subtest 'secrets and key path from the environment' => sub {
    plan skip_all => 'lab/docker is not running (make lab-docker-start)' unless lab_ready('lab/docker');
    local $ENV{CBT_PASSWORD}        = 'cbt-pass';
    local $ENV{CBT_ENABLE_PASSWORD} = 'cbt-enable';
    local $ENV{CBT_SSH_KEY_FILE}    = $KEY;
    collect_ok( 'env password', ssh_devices( 'lab/docker', auth => 'password', enable_password => undef ) );
    collect_ok( 'env key',      ssh_devices( 'lab/docker', auth => 'publickey', enable_password => undef ) );
};

subtest 'authentication failures fail that device only' => sub {
    plan skip_all => 'lab/docker is not running (make lab-docker-start)' unless lab_ready('lab/docker');
    my @devs = ssh_devices( 'lab/docker', auth => 'password', password => 'cbt-pass' );
    $devs[0]{password} = 'wrong';
    $devs[2]{password} = 'wrong';
    my ( $rc, $stdout ) = run_collect( write_inventory(@devs) );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TKY-ENB-0001.*FAILED: login failed for cbtadmin/, 'AX-4000: reports the login failure';
    like $stdout, qr/OSK-ENB-0102.*OK/,                               'other device still collected';
    like $stdout, qr/NGY-GNB-0203.*FAILED: login failed for cbtadmin/, 'BG-7 standalone script: same report';
    like $stdout, qr/1\/3 devices collected/,                         'summary';

    my $other = "$TMP/other_key";
    system( 'ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', $other ) == 0 or die 'ssh-keygen failed';
    ( $rc, $stdout ) = run_collect( write_inventory( ( ssh_devices( 'lab/docker', auth => 'publickey', key_file => $other ) )[0] ) );
    like $stdout, qr/FAILED: login failed for cbtadmin/, 'unknown key is rejected';
};

subtest 'unknown host key is refused with host_key_check = yes' => sub {
    plan skip_all => 'lab/docker is not running (make lab-docker-start)' unless lab_ready('lab/docker');
    my ($dev) = ssh_devices( 'lab/docker', password => 'cbt-pass', host_key_check => 'yes', known_hosts => "$TMP/empty_known_hosts" );
    my ( $rc, $stdout ) = run_collect( write_inventory($dev) );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/FAILED: ssh connect to .*Host key verification failed/, 'host key verification';
};

subtest 'wrong enable password is reported over SSH' => sub {
    plan skip_all => 'lab/ssh is not running (make lab-ssh-start)' unless lab_ready('lab/ssh');
    my ($dev) = ssh_devices( 'lab/ssh', auth => 'publickey', key_file => $KEY, enable_password => 'wrong' );
    my ( $rc, $stdout ) = run_collect( write_inventory($dev) );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TKY-ENB-0001.*FAILED: enable failed/, 'enable failure is not mistaken for success';
};

subtest 'Telnet and SSH collect the same configuration' => sub {
    plan skip_all => 'Net::Telnet is not installed' unless have_net_telnet();
    plan skip_all => 'no SSH lab is running' unless %collected;
    my ( $ports, $pid ) = start_telnet_sim( map { [ $_->[1], $_->[0] ] } @DEVICES );
    my @telnet = map {
        {
            name            => $_->[0],
            protocol        => 'telnet',
            host            => '127.0.0.1',
            port            => $ports->{ $_->[0] },
            model           => $_->[2],
            sw              => $_->[3],
            user            => 'cbtadmin',
            password        => 'cbt-pass',
            enable_password => 'cbt-enable',
        }
    } @DEVICES;
    my $before = collect_ok( 'telnet', @telnet );
    for my $label ( sort keys %collected ) {
        is_deeply $collected{$label}{ $_->[0] }, $before->{ $_->[0] }, "$_->[0]: telnet == $label" for @DEVICES;
    }

    my ($lab) = grep { lab_ready($_) } sort keys %LAB;
    my @ssh = ssh_devices( $lab, auth => 'publickey', key_file => $KEY );
    collect_ok( "mixed telnet + ssh ($lab)", $telnet[0], @ssh[ 1, 2 ] );
    kill 'TERM', $pid;
    waitpid $pid, 0;
};

done_testing;

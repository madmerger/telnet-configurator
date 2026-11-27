# SSH collection against the local labs. Each part is skipped when its lab is not running:
#   make lab-ssh-start     (public key, 127.0.0.1:2201-2203)
#   make lab-docker-start  (password + key, 127.0.0.1:2401-2403)
# The same devices are also collected over Telnet (own simulator) and the results must be
# identical apart from the "!! CBT collected" header line.
use strict;
use warnings;
use Test::More;
use File::Temp ();
use FindBin;
use lib "$FindBin::Bin/lib";
use TestLab qw(root start_telnet_sim write_inventory run_collect expected_sections parse_sections ports_open body_without_header);

eval { require Net::OpenSSH; require IO::Pty; 1 } or plan skip_all => 'Net::OpenSSH / IO::Pty not installed';

# Hostnames and ports as in sim/devices.conf (lab/ssh = telnet - 100, lab/docker = telnet + 100).
my %devices = (
    'TKY-ENB-0001' => { profile => 'ax4000-r5', model => 'AX-4000', sw => 'R5.2.1',      lab_ssh => 2201, lab_docker => 2401 },
    'OSK-ENB-0102' => { profile => 'ax4000-r6', model => 'AX-4000', sw => 'R6.1.0',      lab_ssh => 2202, lab_docker => 2402 },
    'NGY-GNB-0203' => { profile => 'bg7-v200',  model => 'BG-7',    sw => 'V200R003C10', lab_ssh => 2203, lab_docker => 2403 },
);
my @names = sort keys %devices;
my $key   = root() . '/lab/.state/cbt_id_ed25519';
my $me    = getpwuid($<);
my $lab_known = root() . '/lab/.state/known_hosts';    # written by lab/keys.sh

# Secrets are passed through ${NAME} references, as in production inventories.
$ENV{CBT_TEST_SSH_PASSWORD}   = 'cbt-pass';
$ENV{CBT_TEST_ENABLE_PASSWORD} = 'cbt-enable';
$ENV{CBT_TEST_SSH_KEY}        = $key;

sub device {
    my ( $name, %extra ) = @_;
    return {
        name            => $name,
        host            => '127.0.0.1',
        model           => $devices{$name}{model},
        sw              => $devices{$name}{sw},
        enable_password => '${CBT_TEST_ENABLE_PASSWORD}',
        %extra,
    };
}

sub ssh_device {
    my ( $name, $lab, $auth, %extra ) = @_;
    return device(
        $name,
        protocol       => 'ssh',
        port           => $devices{$name}{$lab},
        auth           => $auth,
        known_hosts    => $lab_known,
        user           => $lab eq 'lab_ssh' ? $me : 'cbtadmin',
        ( $auth eq 'key' ? ( key_file => '${CBT_TEST_SSH_KEY}' ) : ( password => '${CBT_TEST_SSH_PASSWORD}' ) ),
        %extra,
    );
}

# Telnet baseline from a private simulator.
my ( $ports, $pid ) = start_telnet_sim( map { [ $devices{$_}{profile}, $_ ] } @names );
END { kill 'TERM', $pid if $pid }
my ( $trc, $tout, $telnet_dir ) = run_collect(
    write_inventory( map { device( $_, port => $ports->{$_}, user => 'cbtadmin', password => 'cbt-pass' ) } @names ) );
is $trc, 0, 'telnet baseline collected' or diag $tout;

sub check_ssh_collect {
    my ( $lab, $auth ) = @_;
    my ( $rc, $stdout, $outdir ) = run_collect( write_inventory( map { ssh_device( $_, $lab, $auth ) } @names ) );
    is $rc, 0, 'all devices collected over ssh' or diag $stdout;
    like $stdout, qr/ssh\/$auth/, "reported as ssh/$auth";
    for my $name (@names) {
        my $file = "$outdir/$name/latest.cfg";
        ok -s $file, "$name: output written" or next;
        is_deeply parse_sections($file), expected_sections( $devices{$name}{profile}, $name ),
          "$name: collected output matches the device";
        is body_without_header($file), body_without_header("$telnet_dir/$name/latest.cfg"),
          "$name: identical to the telnet collection (except header)";
    }
}

subtest 'lab/ssh: public key auth' => sub {
    plan skip_all => 'lab/ssh not running (make lab-ssh-start)' unless ports_open( 2201 .. 2203 ) && -r $key;
    check_ssh_collect( 'lab_ssh', 'key' );
};

subtest 'lab/docker: password auth' => sub {
    plan skip_all => 'lab/docker not running (make lab-docker-start)' unless ports_open( 2401 .. 2403 );
    check_ssh_collect( 'lab_docker', 'password' );
};

subtest 'lab/docker: public key auth' => sub {
    plan skip_all => 'lab/docker not running (make lab-docker-start)' unless ports_open( 2401 .. 2403 ) && -r $key;
    check_ssh_collect( 'lab_docker', 'key' );
};

subtest 'lab/docker: telnet and ssh devices in one inventory' => sub {
    plan skip_all => 'lab/docker not running (make lab-docker-start)' unless ports_open( 2401 .. 2403 );
    my ( $rc, $stdout, $outdir ) = run_collect(
        write_inventory(
            device( 'TKY-ENB-0001', port => $ports->{'TKY-ENB-0001'}, user => 'cbtadmin', password => 'cbt-pass' ),
            ssh_device( 'NGY-GNB-0203', 'lab_docker', 'password' ),
        )
    );
    is $rc, 0, 'both collected' or diag $stdout;
    like $stdout, qr/TKY-ENB-0001 .* telnet .*OK/, 'telnet device';
    like $stdout, qr/NGY-GNB-0203 .* ssh\/password .*OK/, 'ssh device';
};

subtest 'lab/docker: wrong password fails that device only' => sub {
    plan skip_all => 'lab/docker not running (make lab-docker-start)' unless ports_open( 2401 .. 2403 );
    my ( $rc, $stdout ) = run_collect(
        write_inventory(
            ssh_device( 'TKY-ENB-0001', 'lab_docker', 'password', password => 'wrong' ),
            ssh_device( 'OSK-ENB-0102', 'lab_docker', 'password' ),
        )
    );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TKY-ENB-0001 .*FAILED: ssh login to 127\.0\.0\.1:2401 failed \(password auth\)/, 'reports the login failure';
    like $stdout, qr/OSK-ENB-0102 .*OK/, 'other device still collected';
    like $stdout, qr/1\/2 devices collected/, 'summary';
};

subtest 'lab/ssh: wrong enable password and missing key are reported' => sub {
    plan skip_all => 'lab/ssh not running (make lab-ssh-start)' unless ports_open( 2201 .. 2203 ) && -r $key;
    my ( $rc, $stdout ) = run_collect(
        write_inventory(
            ssh_device( 'TKY-ENB-0001', 'lab_ssh', 'key', enable_password => 'bad' ),
            ssh_device( 'OSK-ENB-0102', 'lab_ssh', 'key', key_file => '/nonexistent/id_ed25519' ),
        )
    );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TKY-ENB-0001 .*FAILED: enable failed/,                 'bad enable password';
    like $stdout, qr/OSK-ENB-0102 .*FAILED: ssh key file .* is not readable/, 'unreadable key file';
};

subtest 'lab/ssh: strict host key checking (default) with pre-registered known_hosts' => sub {
    plan skip_all => 'lab/ssh not running (make lab-ssh-start)' unless ports_open( 2201 .. 2203 ) && -r $key;
    my $dir   = File::Temp::tempdir( CLEANUP => 1 );
    my $known = "$dir/known hosts";    # a path with a space must work
    system( 'cp', $lab_known, $known ) == 0 or plan skip_all => "no $lab_known (restart the lab)";
    open my $fh, '>', "$dir/empty" or die $!;
    close $fh;

    my %strict = ( host_key_check => undef );    # not set: the default (yes) applies
    my ( $rc, $stdout, $outdir ) = run_collect(
        write_inventory( map { ssh_device( $_, 'lab_ssh', 'key', %strict, known_hosts => $known ) } @names ) );
    is $rc, 0, 'all devices collected with registered host keys' or diag $stdout;
    is body_without_header("$outdir/$_/latest.cfg"), body_without_header("$telnet_dir/$_/latest.cfg"),
      "$_: identical to the telnet collection" for @names;

    ( $rc, $stdout ) = run_collect(
        write_inventory(
            ssh_device( 'TKY-ENB-0001', 'lab_ssh', 'key', %strict, known_hosts => "$dir/empty" ),
            ssh_device( 'NGY-GNB-0203', 'lab_ssh', 'key', %strict, known_hosts => "$dir/empty" ),
            ssh_device( 'OSK-ENB-0102', 'lab_ssh', 'key', %strict, known_hosts => "$dir/missing" ),
        )
    );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TKY-ENB-0001 .*FAILED: ssh login .*Host key verification failed/, 'unknown host key refused (AX-4000)';
    like $stdout, qr/NGY-GNB-0203 .*Host key verification failed.*\n.*FAILED/, 'unknown host key refused (BG-7)';
    like $stdout, qr/OSK-ENB-0102 .*FAILED: known_hosts file .* is not readable/, 'missing known_hosts file';

    ( $rc, $stdout ) = run_collect(
        write_inventory(
            ssh_device( 'TKY-ENB-0001', 'lab_ssh', 'key', %strict, known_hosts => undef ),
            ssh_device( 'OSK-ENB-0102', 'lab_ssh', 'key', %strict, known_hosts => $known ),
        )
    );
    like $stdout, qr/TKY-ENB-0001 .*FAILED: host_key_check = yes needs known_hosts/, 'no known_hosts: only that device fails';
    like $stdout, qr/OSK-ENB-0102 .*OK/, 'other devices are still collected';

    {
        local $ENV{HOME} = $dir;
        require lib;
        lib->import( root() . '/lib' );
        require CBT::SSH;
        my $s = eval {
            CBT::SSH->open( host => '127.0.0.1', port => 2201, user => $me, auth => 'key', key_file => $key,
                known_hosts => '~/known hosts', prompt => '/[>#]\s*$/' );
        };
        ok $s, 'known_hosts = ~/... is expanded like OpenSSH does' or diag $@;
        $s->close if $s;
    }
};

sub zombie_children {
    my @z;
    for my $stat ( glob '/proc/[0-9]*/stat' ) {
        open my $fh, '<', $stat or next;
        my $line = <$fh> // next;
        my ( $pid, $state, $ppid ) = $line =~ /^(\d+) \(.*\) (\S) (\d+)/ or next;
        push @z, $pid if $ppid == $$ && $state eq 'Z';
    }
    return @z;
}

subtest 'lab/ssh: session log after enable, ssh child reaped on failure' => sub {
    plan skip_all => 'lab/ssh not running (make lab-ssh-start)' unless ports_open( 2201 .. 2203 ) && -r $key;
    require lib;
    lib->import( root() . '/lib' );
    require CBT::Collector::AX4000_R5;
    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    my %dev = ( %{ ssh_device( 'TKY-ENB-0001', 'lab_ssh', 'key' ) }, key_file => $key, enable_password => 'cbt-enable' );

    my $c = CBT::Collector::AX4000_R5->new( timeout => 10, session_log => "$dir/ok.log" );
    ok eval { $c->collect( \%dev ); 1 }, 'collected' or diag $@;
    my $log = do { local ( @ARGV, $/ ) = "$dir/ok.log"; <> };
    like $log, qr/terminal length 0/, 'commands after enable are in the session log';
    like $log, qr/show cell status/, 'last command is in the session log';
    unlike $log, qr/cbt-enable/, 'enable password is not in the session log';

    for ( 1 .. 3 ) {
        my $bad = CBT::Collector::AX4000_R5->new( timeout => 10, session_log => "$dir/bad.log" );
        ok !eval { $bad->collect( { %dev, enable_password => 'bad' } ); 1 }, "bad enable password fails ($_)";
    }
    SKIP: {
        skip 'no /proc to inspect child processes', 1 unless -r "/proc/$$/stat";
        is_deeply [ zombie_children() ], [], 'no zombie ssh children after failed collections';
    }
};

done_testing;

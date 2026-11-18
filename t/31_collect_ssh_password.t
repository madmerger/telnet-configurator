# SSH with password auth (and key auth mixed per device). Needs `make lab-docker-start`
# (lab/docker, 127.0.0.1:2401-2403, cbtadmin / cbt-pass): a non-root sshd cannot check passwords.
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use File::Temp qw(tempdir);
use TestLab qw(lab_devices ssh_lab_up ssh_inventory write_inventory run_collect parse_sections expected_sections lab_key);

plan skip_all => 'lab/docker not running (make lab-docker-start)' unless ssh_lab_up(2400);
my %lab = ( base => 2400, user => 'cbtadmin' );

subtest 'password auth, all models' => sub {
    my $kh = tempdir( CLEANUP => 1 ) . '/known_hosts';
    my ( $rc, $stdout, $out ) =
      run_collect( write_inventory( ssh_inventory( %lab, auth => [ ('password') x 3 ], known_hosts => $kh ) ) );
    is $rc, 0, 'all devices collected' or diag $stdout;
    like $stdout, qr/ssh\/password/, 'collected over ssh with password auth';
    for my $d ( lab_devices() ) {
        is_deeply parse_sections("$out/$d->{name}/latest.cfg"), expected_sections( $d->{profile}, $d->{name} ),
          "$d->{name}: collected output matches the device";
    }
};

subtest 'password and key auth chosen per device, secrets from the environment' => sub {
    plan skip_all => 'lab key missing' unless -r lab_key();
    local $ENV{T_CBT_PASSWORD} = 'cbt-pass';
    my $kh  = tempdir( CLEANUP => 1 ) . '/known_hosts';
    my @inv = ssh_inventory( %lab, auth => [ 'password', 'key', 'password' ], known_hosts => $kh );
    $_->{password} = '${T_CBT_PASSWORD}' for grep { $_->{auth} eq 'password' } @inv;
    my ( $rc, $stdout, $out ) = run_collect( write_inventory(@inv) );
    is $rc, 0, 'all devices collected' or diag $stdout;
    like $stdout, qr/OSK-ENB-0102 .*ssh\/key/,          'R6 over key auth';
    like $stdout, qr/NGY-GNB-0203 .*ssh\/password/,     'BG-7 over password auth';
    ok -s "$out/$_->{name}/latest.cfg", "$_->{name}: output written" for lab_devices();
};

subtest 'wrong password fails that device only' => sub {
    my $kh  = tempdir( CLEANUP => 1 ) . '/known_hosts';
    my @inv = ssh_inventory( %lab, auth => [ 'password', 'password', 'password' ], known_hosts => $kh, password => 'wrong' );
    $inv[1]{password} = 'cbt-pass';
    my ( $rc, $stdout ) = run_collect( write_inventory(@inv) );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TKY-ENB-0001 .*FAILED: ssh connect .*Permission denied/, 'library collector reports it';
    like $stdout, qr/NGY-GNB-0203 .*FAILED: ssh connect .*Permission denied/, 'standalone script reports it';
    like $stdout, qr/OSK-ENB-0102 .*OK/, 'other devices are still collected';
};

subtest 'wrong enable password is reported after ssh login' => sub {
    my $kh = tempdir( CLEANUP => 1 ) . '/known_hosts';
    my ($dev) = ssh_inventory( %lab, auth => ['password'], known_hosts => $kh );
    my ( $rc, $stdout ) = run_collect( write_inventory( { %$dev, enable_password => 'nope' } ) );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/FAILED: enable failed/, 'enable failure';
};

done_testing;

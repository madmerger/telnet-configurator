# SSH with public key auth, all models. Needs `make lab-ssh-start` (lab/ssh, 127.0.0.1:2201-2203);
# lab/docker (2401-2403) is used as well if it is running.
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use File::Temp qw(tempdir);
use TestLab qw(lab_devices ssh_lab_up ssh_inventory write_inventory run_collect parse_sections expected_sections lab_key);

my %labs = (
    'lab/ssh'    => { base => 2200, user => scalar getpwuid($<) },
    'lab/docker' => { base => 2400, user => 'cbtadmin' },
);
my @up = grep { ssh_lab_up( $labs{$_}{base} ) } sort keys %labs;
plan skip_all => 'no SSH lab running (make lab-ssh-start or make lab-docker-start)' unless @up && -r lab_key();

for my $lab (@up) {
    subtest "$lab: key auth" => sub {
        my $kh  = tempdir( CLEANUP => 1 ) . '/known_hosts';
        my $inv = write_inventory( ssh_inventory( %{ $labs{$lab} }, auth => [ ('key') x 3 ], known_hosts => $kh ) );
        my ( $rc, $stdout, $out ) = run_collect($inv);
        is $rc, 0, 'all devices collected' or diag $stdout;
        like $stdout, qr/ssh\/key/, 'collected over ssh with key auth';
        for my $d ( lab_devices() ) {
            is_deeply parse_sections("$out/$d->{name}/latest.cfg"), expected_sections( $d->{profile}, $d->{name} ),
              "$d->{name}: collected output matches the device";
        }
        ok -s $kh, 'accept-new recorded the host keys in known_hosts';

        ( $rc, $stdout ) = run_collect($inv);
        is $rc, 0, 'second run verifies against the recorded keys' or diag $stdout;
    };
}

subtest 'strict host key checking rejects an unknown host' => sub {
    my $lab = $labs{ $up[0] };
    my $kh  = tempdir( CLEANUP => 1 ) . '/known_hosts';
    open my $fh, '>', $kh or die $!;
    close $fh;
    my ($dev) = ssh_inventory( %$lab, auth => ['key'], known_hosts => $kh, host_key_check => 'yes' );
    my ( $rc, $stdout ) = run_collect( write_inventory($dev) );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/FAILED: ssh connect .*Host key verification failed/, 'reports the host key failure';
};

subtest 'wrong key is rejected' => sub {
    my $lab = $labs{ $up[0] };
    my $dir = tempdir( CLEANUP => 1 );
    system( 'ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', "$dir/other" ) == 0 or die 'ssh-keygen failed';
    my @inv = ssh_inventory( %$lab, auth => [ ('key') x 3 ], known_hosts => "$dir/known_hosts" );
    $_->{key_file} = "$dir/other" for @inv;
    my ( $rc, $stdout ) = run_collect( write_inventory( @inv[ 0, 2 ] ) );
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TKY-ENB-0001.*FAILED: ssh connect .*Permission denied/, 'library collector reports it';
    like $stdout, qr/NGY-GNB-0203.*FAILED: ssh connect .*Permission denied/, 'standalone script reports it';
};

done_testing;

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestLab qw(root wait_port write_inventory run_collect parse_sections expected_sections);

# Runs against the SSH labs if they are up (make lab-ssh-start / make lab-docker-start).
my @devices = ( [ 'ax4000-r5', 'TKY-ENB-0001', 'AX-4000', 'R5.2.1' ],
                [ 'ax4000-r6', 'OSK-ENB-0102', 'AX-4000', 'R6.1.0' ],
                [ 'bg7-v200',  'NGY-GNB-0203', 'BG-7',    'V200R003C10' ] );
my $key = root() . '/lab/.state/cbt_id_ed25519';
my $kh  = root() . '/lab/.state/known_hosts';

my %labs = (
    'lab/ssh key auth'         => { base => 2200, user => scalar getpwuid($<), auth => [ 'key', 'key', 'key' ] },
    'lab/docker password+key'  => { base => 2400, user => 'cbtadmin',          auth => [ 'password', 'key', 'password' ] },
);

my $ran = 0;
for my $lab ( sort keys %labs ) {
    my $l = $labs{$lab};
    unless ( wait_port( $l->{base} + 1, 0.1 ) ) { note "$lab not running, skipped"; next }
    $ran++;
    my @inv = map {
        my ( $p, $name, $model, $sw ) = @{ $devices[$_] };
        my $auth = $l->{auth}[$_];
        { name => $name, host => '127.0.0.1', port => $l->{base} + 1 + $_, protocol => 'ssh', auth => $auth,
          model => $model, sw => $sw, user => $l->{user}, known_hosts => $kh, enable_password => 'cbt-enable',
          ( $auth eq 'key' ? ( key_file => $key ) : ( password => 'cbt-pass' ) ) }
    } 0 .. $#devices;

    my ( $rc, $stdout, $out ) = run_collect( write_inventory(@inv) );
    is $rc, 0, "$lab: collect exits 0" or diag $stdout;
    for my $d (@devices) {
        my $got  = parse_sections("$out/$d->[1]/latest.cfg");
        my $want = expected_sections( $d->[0], $d->[1] );
        is_deeply $got, $want, "$lab: $d->[1] matches device output";
    }

    if ( grep { $_ eq 'password' } @{ $l->{auth} } ) {
        my ($bad) = grep { $_->{auth} eq 'password' } @inv;
        my ( $rc2, $stdout2 ) = run_collect( write_inventory( { %$bad, password => 'wrong' } ) );
        isnt $rc2, 0, "$lab: wrong ssh password fails";
        like $stdout2, qr/FAILED: ssh connect/, "$lab: failure is reported";
    }
}
plan skip_all => 'no SSH lab running (make lab-ssh-start or make lab-docker-start)' unless $ran;
done_testing;

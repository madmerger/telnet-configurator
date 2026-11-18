use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestLab qw(start_telnet_sim write_inventory run_collect expected_sections parse_sections);

my %devices = (
    'TST-ENB-0001' => { profile => 'ax4000-r5', model => 'AX-4000', sw => 'R5.2.1' },
    'TST-ENB-0002' => { profile => 'ax4000-r6', model => 'AX-4000', sw => 'R6.1.0' },
    'TST-GNB-0003' => { profile => 'bg7-v200',  model => 'BG-7',    sw => 'V200R003C10' },
);
my ( $ports, $pid ) = start_telnet_sim( map { [ $devices{$_}{profile}, $_ ] } sort keys %devices );
END { kill 'TERM', $pid if $pid }

my $inv = write_inventory(
    map {
        {
            name            => $_,
            host            => '127.0.0.1',
            port            => $ports->{$_},
            model           => $devices{$_}{model},
            sw              => $devices{$_}{sw},
            user            => 'cbtadmin',
            password        => 'cbt-pass',
            enable_password => 'cbt-enable',
        }
    } sort keys %devices
);

my ( $rc, $stdout, $outdir ) = run_collect($inv);
is $rc, 0, 'all devices collected' or diag $stdout;

for my $name ( sort keys %devices ) {
    my $file = "$outdir/$name/latest.cfg";
    ok -s $file, "$name: output written" or next;
    my $got  = parse_sections($file);
    my $want = expected_sections( $devices{$name}{profile}, $name );
    is_deeply $got, $want, "$name: collected output matches the device";
}

subtest 'bad credentials fail that device only' => sub {
    my $bad = write_inventory(
        {
            name            => 'TST-ENB-0001',
            host            => '127.0.0.1',
            port            => $ports->{'TST-ENB-0001'},
            model           => 'AX-4000',
            sw              => 'R5.2.1',
            user            => 'cbtadmin',
            password        => 'wrong',
            enable_password => 'cbt-enable',
        }
    );
    my ( $rc, $stdout ) = run_collect($bad);
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TST-ENB-0001.*FAILED: login failed/, 'reports the login failure';
};

subtest 'bad enable password fails that device' => sub {
    my $bad = write_inventory(
        {
            name            => 'TST-ENB-0002',
            host            => '127.0.0.1',
            port            => $ports->{'TST-ENB-0002'},
            model           => 'AX-4000',
            sw              => 'R6.1.0',
            user            => 'cbtadmin',
            password        => 'cbt-pass',
            enable_password => 'wrong',
        }
    );
    my ( $rc, $stdout ) = run_collect($bad);
    isnt $rc, 0, 'non-zero exit';
    like $stdout, qr/TST-ENB-0002.*FAILED: enable failed/, 'reports the enable failure';
};

done_testing;

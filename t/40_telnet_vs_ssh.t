# The same devices collected over Telnet and over SSH give identical files
# (apart from the "!! CBT collected ... at <time>" header). Needs an SSH lab.
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use File::Temp qw(tempdir);
use TestLab qw(lab_devices ssh_lab_up ssh_inventory start_telnet_sim write_inventory run_collect read_without_header lab_key);

my @ssh;
push @ssh, [ 'lab/ssh key',             { base => 2200, user => scalar getpwuid($<), auth => [ ('key') x 3 ] } ]
  if ssh_lab_up(2200) && -r lab_key();
push @ssh, [ 'lab/docker password',     { base => 2400, user => 'cbtadmin', auth => [ ('password') x 3 ] } ] if ssh_lab_up(2400);
push @ssh, [ 'lab/docker password+key', { base => 2400, user => 'cbtadmin', auth => [ 'password', 'key', 'password' ] } ]
  if ssh_lab_up(2400) && -r lab_key();
plan skip_all => 'no SSH lab running (make lab-ssh-start or make lab-docker-start)' unless @ssh;

my @devs = lab_devices();
my ( $ports, $pid ) = start_telnet_sim( map { [ $_->{profile}, $_->{name} ] } @devs );
END { kill 'TERM', $pid if $pid }

my ( $rc, $stdout, $telnet_out ) = run_collect(
    write_inventory(
        map {
            {
                name => $_->{name}, host => '127.0.0.1', port => $ports->{ $_->{name} }, model => $_->{model}, sw => $_->{sw},
                user => 'cbtadmin', password => 'cbt-pass', enable_password => 'cbt-enable',
            }
        } @devs
    )
);
is $rc, 0, 'telnet: all devices collected' or diag $stdout;

for my $s (@ssh) {
    my ( $label, $lab ) = @$s;
    my $kh = tempdir( CLEANUP => 1 ) . '/known_hosts';
    my ( $rc, $stdout, $ssh_out ) = run_collect( write_inventory( ssh_inventory( %$lab, known_hosts => $kh ) ) );
    is $rc, 0, "$label: all devices collected" or diag $stdout;
    for my $d (@devs) {
        my ( $t, $x ) = map { "$_/$d->{name}/latest.cfg" } $telnet_out, $ssh_out;
        is read_without_header($x), read_without_header($t), "$label: $d->{name} identical to telnet";
    }
}

done_testing;

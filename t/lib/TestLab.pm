package TestLab;
# Helpers shared by the tests: start simulators, run the collector,
# compare what was collected with what the simulated device prints.
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use Exporter 'import';
use lib "$FindBin::Bin/../sim/lib";
use BSSim::Profile;

our @EXPORT_OK = qw(root free_port start_telnet_sim write_inventory run_collect expected_sections parse_sections wait_port
  lab_devices ssh_lab_up lab_key ssh_inventory read_without_header);
our $ROOT = "$FindBin::Bin/..";

sub root { $ROOT }

sub free_port {
    my $s = IO::Socket::INET->new( LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 1 ) or die $!;
    my $p = $s->sockport;
    close $s;
    return $p;
}

sub wait_port {
    my ( $port, $secs ) = @_;
    for ( 1 .. ( $secs || 5 ) * 10 ) {
        return 1 if IO::Socket::INET->new( PeerAddr => '127.0.0.1', PeerPort => $port );
        select undef, undef, undef, 0.1;
    }
    return 0;
}

# devices: [ [profile, hostname], ... ] -> returns { hostname => port }, pid
sub start_telnet_sim {
    my (@devices) = @_;
    my %ports = map { $_->[1] => free_port() } @devices;
    my @args  = map { ( '--device', "$_->[0]:$ports{$_->[1]}:$_->[1]" ) } @devices;
    my $pid   = fork // die "fork: $!";
    if ( !$pid ) {
        exec $^X, "$ROOT/sim/bs-sim.pl", '--quiet', @args;
        die "exec: $!";
    }
    wait_port($_) or die "simulator did not start on port $_\n" for values %ports;
    return ( \%ports, $pid );
}

sub write_inventory {
    my (@devs) = @_;
    my $dir  = tempdir( CLEANUP => 1 );
    my $file = "$dir/inventory.conf";
    open my $fh, '>', $file or die $!;
    for my $d (@devs) {
        print $fh "[$d->{name}]\n";
        print $fh "$_ = $d->{$_}\n" for grep { $_ ne 'name' } sort keys %$d;
        print $fh "\n";
    }
    close $fh;
    return $file;
}

sub run_collect {
    my ( $inventory, @extra ) = @_;
    my $out = tempdir( CLEANUP => 1 );
    my $log = tempdir( CLEANUP => 1 );
    my $cmd = join ' ', map { quotemeta } $^X, "$ROOT/bin/cbt-collect", '-i', $inventory, '-o', $out, '--logdir', $log,
      '--timeout', 10, @extra;
    my $stdout = `$cmd 2>&1`;
    return ( $? >> 8, $stdout, $out );
}

sub parse_sections {
    my ($file) = @_;
    open my $fh, '<', $file or die "$file: $!";
    my ( %s, $cur );
    while (<$fh>) {
        if (/^!! ===== (.+) =====$/) { $cur = $1; $s{$cur} = ''; next }
        $s{$cur} .= $_ if defined $cur;
    }
    return \%s;
}

# The devices of the fixed local labs (sim/devices.conf): Telnet 23xx, lab/ssh 22xx, lab/docker 24xx.
sub lab_devices {
    return (
        { name => 'TKY-ENB-0001', profile => 'ax4000-r5', model => 'AX-4000', sw => 'R5.2.1',      telnet => 2301 },
        { name => 'OSK-ENB-0102', profile => 'ax4000-r6', model => 'AX-4000', sw => 'R6.1.0',      telnet => 2302 },
        { name => 'NGY-GNB-0203', profile => 'bg7-v200',  model => 'BG-7',    sw => 'V200R003C10', telnet => 2303 },
    );
}

sub lab_key { "$ROOT/lab/.state/cbt_id_ed25519" }

# True if an sshd of the given lab (base 2200 or 2400) answers with an SSH banner.
sub ssh_lab_up {
    my ($base) = @_;
    for my $port ( map { $base + $_ } 1 .. 3 ) {
        my $s = IO::Socket::INET->new( PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1 ) or return 0;
        my $banner = '';
        my $rin    = '';
        vec( $rin, fileno $s, 1 ) = 1;
        sysread $s, $banner, 64 if select( $rin, undef, undef, 2 );
        return 0 unless $banner =~ /^SSH-/;
    }
    return 1;
}

# Inventory entries for the lab devices over SSH. %a: base, user, auth => [per device], known_hosts.
sub ssh_inventory {
    my (%a) = @_;
    my @devs = lab_devices();
    return map {
        my $d    = $devs[$_];
        my $auth = $a{auth}[$_];
        {
            name            => $d->{name},
            host            => '127.0.0.1',
            port            => $a{base} + 1 + $_,
            protocol        => 'ssh',
            auth            => $auth,
            user            => $a{user},
            model           => $d->{model},
            sw              => $d->{sw},
            known_hosts     => $a{known_hosts},
            host_key_check  => $a{host_key_check} || 'accept-new',
            enable_password => 'cbt-enable',
            ( $auth eq 'key' ? ( key_file => lab_key() ) : ( password => $a{password} // 'cbt-pass' ) ),
        }
    } grep { defined $a{auth}[$_] } 0 .. $#devs;
}

# Collected file without the "!! CBT collected ... at <timestamp>" header line.
sub read_without_header {
    my ($file) = @_;
    open my $fh, '<', $file or die "$file: $!";
    return join '', grep { !/^!! CBT collected / } <$fh>;
}

sub expected_sections {
    my ( $profile, $host ) = @_;
    my $p = BSSim::Profile->get($profile);
    return { map { $_ => BSSim::Profile->render( $p, $host, $_ ) } keys %{ $p->{commands} } };
}

1;

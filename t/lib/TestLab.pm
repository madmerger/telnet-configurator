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

our @EXPORT_OK =
  qw(root free_port start_telnet_sim write_inventory run_collect expected_sections parse_sections wait_port ports_open body_without_header);
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

# true if something is listening on every given 127.0.0.1 port (used to skip when a lab is down)
sub ports_open {
    my (@ports) = @_;
    for my $p (@ports) {
        IO::Socket::INET->new( PeerAddr => '127.0.0.1', PeerPort => $p, Timeout => 1 ) or return 0;
    }
    return 1;
}

# collected file without the "!! CBT collected ... at TIMESTAMP" header line
sub body_without_header {
    my ($file) = @_;
    open my $fh, '<', $file or die "$file: $!";
    my @lines = <$fh>;
    shift @lines if @lines && $lines[0] =~ /^!! CBT collected /;
    return join '', @lines;
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

sub expected_sections {
    my ( $profile, $host ) = @_;
    my $p = BSSim::Profile->get($profile);
    return { map { $_ => BSSim::Profile->render( $p, $host, $_ ) } keys %{ $p->{commands} } };
}

1;

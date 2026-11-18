package CBT::Inventory;
# Reads the device inventory (INI style, one [section] per device).
# Values may reference environment variables as ${NAME}.
#
# Connection keys (per device):
#   protocol = telnet | ssh          (default: telnet)
#   auth     = password | key        (ssh only, default: password)
#   key_file = PATH                  (required for auth = key)
#   host_key_check = accept-new | yes | no   (ssh only, default: accept-new)
#   known_hosts    = PATH            (ssh only, optional)
use strict;
use warnings;

sub load {
    my ( $class, $file ) = @_;
    open my $fh, '<', $file or die "cannot read inventory $file: $!\n";
    my ( @devices, $cur );
    while ( my $line = <$fh> ) {
        $line =~ s/\r?\n$//;
        next if $line =~ /^\s*([#;]|$)/;
        if ( $line =~ /^\s*\[([^\]]+)\]\s*$/ ) {
            $cur = { name => $1 };
            push @devices, $cur;
            next;
        }
        die "$file:$.: expected key = value\n" unless $line =~ /^\s*([\w.-]+)\s*=\s*(.*?)\s*$/;
        die "$file:$.: key outside of a [device] section\n" unless $cur;
        my ( $k, $v ) = ( $1, $2 );
        $v =~ s/\$\{(\w+)\}/$ENV{$1} \/\/ ''/ge;
        $cur->{$k} = $v;
    }
    for my $d (@devices) {
        for my $req (qw(host model sw)) {
            die "$file: device [$d->{name}] is missing '$req'\n" unless defined $d->{$req};
        }
        $d->{protocol} = lc( $d->{protocol} // 'telnet' );
        die "$file: device [$d->{name}]: protocol must be telnet or ssh\n" unless $d->{protocol} =~ /^(telnet|ssh)$/;
        next unless $d->{protocol} eq 'ssh';
        $d->{auth} = lc( $d->{auth} // 'password' );
        die "$file: device [$d->{name}]: auth must be password or key\n" unless $d->{auth} =~ /^(password|key)$/;
        die "$file: device [$d->{name}]: auth = key needs key_file\n" if $d->{auth} eq 'key' && !defined $d->{key_file};
    }
    return \@devices;
}

1;

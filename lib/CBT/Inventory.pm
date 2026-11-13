package CBT::Inventory;
# Reads the device inventory (INI style, one [section] per device).
# Values may reference environment variables as ${NAME}.
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
    }
    return \@devices;
}

1;

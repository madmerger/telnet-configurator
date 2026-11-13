package CBT::Inventory;
# Reads the device inventory (INI style, one [section] per device).
# Values may reference environment variables as ${NAME}.
#   protocol = telnet | ssh      (default telnet; port defaults to 23 / 22)
#   auth     = password | key    (ssh only; default key if key_file is set)
#   key_file, known_hosts        (ssh only)
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
        $d->{protocol} ||= 'telnet';
        die "$file: device [$d->{name}]: protocol must be telnet or ssh\n" unless $d->{protocol} =~ /^(telnet|ssh)$/;
        $d->{port} ||= $d->{protocol} eq 'ssh' ? 22 : 23;
        if ( $d->{protocol} eq 'ssh' ) {
            $d->{auth} ||= $d->{key_file} ? 'key' : 'password';
            die "$file: device [$d->{name}]: auth must be password or key\n" unless $d->{auth} =~ /^(password|key)$/;
            die "$file: device [$d->{name}]: auth = key needs key_file\n" if $d->{auth} eq 'key' && !$d->{key_file};
        }
    }
    return \@devices;
}

1;

package CBT::Inventory;
# Reads the device inventory (INI style, one [section] per device).
# Values may reference environment variables as ${NAME}.
#
# Transport keys (all optional, so existing Telnet inventories keep working):
#   protocol       = telnet | ssh             default telnet
#   port                                      default 23 (telnet) / 22 (ssh)
#   auth           = password | key           ssh only, default password
#   key_file       = private key              auth = key
#   key_passphrase = passphrase of key_file   auth = key, if the key is encrypted
#   known_hosts    = known_hosts file         default: ssh's own (~/.ssh/known_hosts)
#   host_key_check = yes | accept-new         default yes; accept-new records unknown keys (lab)
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
    _check( $file, $_ ) for @devices;
    return \@devices;
}

sub _check {
    my ( $file, $d ) = @_;
    my $where = "$file: device [$d->{name}]";
    for my $req (qw(host model sw)) {
        die "$where is missing '$req'\n" unless defined $d->{$req};
    }
    $d->{protocol} ||= 'telnet';
    die "$where: protocol must be telnet or ssh\n" unless $d->{protocol} =~ /^(?:telnet|ssh)$/;
    $d->{port} ||= $d->{protocol} eq 'ssh' ? 22 : 23;
    if ( $d->{protocol} eq 'telnet' ) {
        for my $k (qw(auth key_file key_passphrase known_hosts host_key_check)) {
            die "$where: '$k' needs protocol = ssh\n" if defined $d->{$k} && length $d->{$k};
        }
        return;
    }
    $d->{auth}           ||= 'password';
    $d->{host_key_check} ||= 'yes';
    die "$where: auth must be password or key\n"           unless $d->{auth} =~ /^(?:password|key)$/;
    die "$where: host_key_check must be yes or accept-new\n" unless $d->{host_key_check} =~ /^(?:yes|accept-new)$/;
    die "$where: auth = key needs key_file\n" if $d->{auth} eq 'key' && !( defined $d->{key_file} && length $d->{key_file} );
    die "$where: auth = password needs password\n"
      if $d->{auth} eq 'password' && !( defined $d->{password} && length $d->{password} );
}

1;

package CBT::Inventory;
# Reads the device inventory (INI style, one [section] per device).
# Values may reference environment variables as ${NAME}; an empty value counts as unset.
#
# Connection keys (per device):
#   protocol        telnet (default) | ssh
#   port            default 23 (telnet) / 22 (ssh)
#   auth            ssh only: password | publickey (default: publickey if key_file is set, else password)
#   key_file        ssh private key                      (fallback: $CBT_SSH_KEY_FILE)
#   known_hosts     ssh known_hosts file                 (fallback: $CBT_SSH_KNOWN_HOSTS, else ssh's default)
#   host_key_check  yes (default) | accept-new | no      (fallback: $CBT_SSH_HOST_KEY_CHECK)
#   password        login password                       (fallback: $CBT_PASSWORD)
#   enable_password privileged mode password             (fallback: $CBT_ENABLE_PASSWORD)
use strict;
use warnings;

my %ENV_FALLBACK = (
    password        => 'CBT_PASSWORD',
    enable_password => 'CBT_ENABLE_PASSWORD',
    key_file        => 'CBT_SSH_KEY_FILE',
    known_hosts     => 'CBT_SSH_KNOWN_HOSTS',
    host_key_check  => 'CBT_SSH_HOST_KEY_CHECK',
);
my %DEFAULT_PORT = ( telnet => 23, ssh => 22 );

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
        _connection_defaults( $file, $d );
    }
    return \@devices;
}

sub _connection_defaults {
    my ( $file, $d ) = @_;
    for my $k ( keys %ENV_FALLBACK ) {
        delete $d->{$k} if defined $d->{$k} && $d->{$k} eq '';
        my $env = $ENV{ $ENV_FALLBACK{$k} };
        $d->{$k} = $env if !defined $d->{$k} && defined $env && $env ne '';
    }
    my $where = "$file: device [$d->{name}]";
    $d->{protocol} = lc( $d->{protocol} // '' ) || 'telnet';
    die "$where: unknown protocol '$d->{protocol}' (telnet or ssh)\n" unless $DEFAULT_PORT{ $d->{protocol} };
    $d->{port} = $DEFAULT_PORT{ $d->{protocol} } unless defined $d->{port} && $d->{port} ne '';
    return if $d->{protocol} ne 'ssh';

    die "$where: ssh needs 'user'\n" unless defined $d->{user} && $d->{user} ne '';
    $d->{auth} = lc( $d->{auth} // '' ) || ( defined $d->{key_file} ? 'publickey' : 'password' );
    die "$where: unknown auth '$d->{auth}' (password or publickey)\n" unless $d->{auth} =~ /^(password|publickey)$/;
    die "$where: auth = publickey needs 'key_file' (or \$CBT_SSH_KEY_FILE)\n"
      if $d->{auth} eq 'publickey' && !defined $d->{key_file};
    $d->{host_key_check} = lc( $d->{host_key_check} // 'yes' );
    die "$where: host_key_check must be yes, accept-new or no\n" unless $d->{host_key_check} =~ /^(yes|accept-new|no)$/;
    for my $k (qw(key_file known_hosts)) {
        $d->{$k} =~ s{^~(?=/|$)}{$ENV{HOME} // '~'}e if defined $d->{$k};
    }
}

1;

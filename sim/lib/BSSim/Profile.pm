package BSSim::Profile;
# Device profiles for the base-station simulator.
# Core Perl only: this runs under sshd ForceCommand, where no local::lib is set up.
use strict;
use warnings;

my %PROFILES = (
    'ax4000-r5' => {
        vendor          => 'Hoshi Networks',
        model           => 'AX-4000',
        sw              => 'R5.2.1',
        kind            => 'eNodeB',
        banner          => "Hoshi Networks AX-4000 eNodeB\r\nUnauthorized access is prohibited.\r\n",
        login_prompt    => 'Username: ',
        password_prompt => 'Password: ',
        user_prompt     => '%s>',
        enable_prompt   => '%s#',
        enable_cmd      => 'enable',
        paging_cmds     => ['terminal length 0'],
        exit_cmds       => [ 'exit', 'logout', 'quit' ],
        privileged_cmds => ['show running-config'],
        commands        => {
            'show version'        => \&_ax_version,
            'show running-config' => \&_ax_running_config,
            'show cell status'    => \&_ax_cell_status,
        },
    },
    'ax4000-r6' => {
        vendor          => 'Hoshi Networks',
        model           => 'AX-4000',
        sw              => 'R6.1.0',
        kind            => 'eNodeB',
        banner          => "Hoshi Networks AX-4000 eNodeB (R6)\r\n*** Authorized personnel only ***\r\n",
        login_prompt    => 'Username: ',
        password_prompt => 'Password: ',
        user_prompt     => '%s[R6]>',
        enable_prompt   => '%s[R6]#',
        enable_cmd      => 'enable',
        # R6 renamed the pager command; R5 syntax is rejected.
        paging_cmds     => ['terminal pager disable'],
        exit_cmds       => [ 'exit', 'logout' ],
        privileged_cmds => ['show running-config'],
        commands        => {
            'show version'        => \&_ax_version,
            'show running-config' => \&_ax_running_config,
            'show cell status'    => \&_ax_cell_status,
        },
    },
    'bg7-v200' => {
        vendor          => 'Tsuki Systems',
        model           => 'BG-7',
        sw              => 'V200R003C10',
        kind            => 'gNodeB',
        banner          => "Tsuki Systems BG-7 gNodeB\r\n",
        login_prompt    => 'login: ',
        password_prompt => 'Password:',
        user_prompt     => '<%s>',
        paging_cmds     => ['screen-length 0 temporary'],
        exit_cmds       => [ 'quit', 'exit' ],
        privileged_cmds => [],
        commands        => {
            'display version'               => \&_bg_version,
            'display current-configuration' => \&_bg_current_config,
            'display nr-cell all'           => \&_bg_cell_status,
        },
    },
);

sub names { return sort keys %PROFILES }

sub get {
    my ( $class, $name ) = @_;
    my $p = $PROFILES{$name} or die "unknown simulator profile '$name' (known: @{[ names() ]})\n";
    return { %$p, name => $name };
}

# Deterministic per-host numbers so every simulated device looks different.
sub _seed {
    my ($host) = @_;
    my $n = 0;
    $n = ( $n * 31 + ord $_ ) % 1_000_003 for split //, $host;
    return $n;
}

sub _ip {
    my ( $host, $net, $off ) = @_;
    my $s = _seed($host);
    return sprintf '%s.%d.%d', $net, ( $s % 200 ) + 10, ( ( $s >> 3 ) + $off ) % 250 + 2;
}

sub _ax_version {
    my ( $p, $host ) = @_;
    my $s = _seed($host);
    return <<"END";
$p->{vendor} $p->{model} $p->{kind}
Software version : $p->{sw}
Hardware revision: HW-C3
Serial number    : AX4K@{[ sprintf '%08d', $s ]}
Uptime           : @{[ $s % 300 ]} days, @{[ $s % 24 ]} hours
END
}

sub _ax_cells {
    my ($host) = @_;
    my $s = _seed($host);
    return map {
        { id => $_, pci => ( $s + $_ * 7 ) % 504, earfcn => ( 1850, 3050, 6300 )[ $_ - 1 ], tac => 4000 + $s % 900 }
    } 1 .. 3;
}

sub _ax_running_config {
    my ( $p, $host ) = @_;
    my $s     = _seed($host);
    my $enbid = 100_000 + $s % 900_000;
    my $cfg   = <<"END";
! $p->{model} running configuration
! software $p->{sw}
!
hostname $host
!
enb
 enb-id $enbid
 plmn 440-50
 tracking-area-code @{[ 4000 + $s % 900 ]}
!
END
    for my $c ( _ax_cells($host) ) {
        $cfg .= <<"END";
cell $c->{id}
 pci $c->{pci}
 earfcn-dl $c->{earfcn}
 bandwidth 20
 tx-power 43.0
 admin-state unlocked
!
END
    }
    $cfg .= <<"END";
interface s1
 local-address @{[ _ip( $host, '10.20', 1 ) ]}
 mme 10.250.1.11 priority 1
 mme 10.250.1.12 priority 2
!
interface x2
 local-address @{[ _ip( $host, '10.21', 1 ) ]}
 neighbor @{[ _ip( $host . 'n1', '10.21', 1 ) ]}
 neighbor @{[ _ip( $host . 'n2', '10.21', 1 ) ]}
!
interface oam
 address @{[ _ip( $host, '172.16', 5 ) ]} 255.255.255.0
 gateway 172.16.0.1
!
ntp server 172.16.0.10
ntp server 172.16.0.11
snmp-server community ******** ro
snmp-server host 172.16.0.20 traps
logging host 172.16.0.30
!
line vty 0 4
 transport input telnet
 login local
!
end
END
    if ( $p->{sw} =~ /^R6/ ) {
        $cfg =~ s/^!\nhostname/!\nfeature son enable\nfeature ca enable\n!\nhostname/m;
    }
    return $cfg;
}

sub _ax_cell_status {
    my ( $p, $host ) = @_;
    my $out = "Cell  PCI  EARFCN  State     UEs\n----  ---  ------  --------  ---\n";
    my $s   = _seed($host);
    $out .= sprintf "%-4d  %-3d  %-6d  %-8s  %d\n", $_->{id}, $_->{pci}, $_->{earfcn}, 'ACTIVE', ( $s >> $_->{id} ) % 180
      for _ax_cells($host);
    return $out;
}

sub _bg_version {
    my ( $p, $host ) = @_;
    my $s = _seed($host);
    return <<"END";
Tsuki Radio Platform Software
TRP software, Version 8.180 ($p->{model} $p->{sw})
Copyright (C) Tsuki Systems
$p->{model} uptime is @{[ $s % 400 ]} days
BOARD TYPE: BG7-MPU  ESN: 21@{[ sprintf '%010d', $s ]}
END
}

sub _bg_current_config {
    my ( $p, $host ) = @_;
    my $s     = _seed($host);
    my $gnbid = 200_000 + $s % 700_000;
    my $cfg   = <<"END";
!Software Version $p->{sw}
#
sysname $host
#
gnb-function
 gnb-id $gnbid gnb-id-length 24
 plmn mcc 440 mnc 50
#
END
    for my $i ( 0 .. 2 ) {
        $cfg .= <<"END";
nr-cell $i
 nr-pci @{[ ( $s + $i * 11 ) % 1008 ]}
 ssb-arfcn @{[ ( 643_296, 650_016, 2_079_167 )[$i] ]}
 bandwidth @{[ ( 100, 100, 200 )[$i] ]}
 tac @{[ 5000 + $s % 900 ]}
 cell-state active
#
END
    }
    $cfg .= <<"END";
interface GigabitEthernet0/0/0
 description NG-C/NG-U to 5GC
 ip address @{[ _ip( $host, '10.30', 1 ) ]} 255.255.255.0
#
interface GigabitEthernet0/0/1
 description OAM
 ip address @{[ _ip( $host, '172.17', 5 ) ]} 255.255.255.0
#
amf-peer 1 ip 10.251.1.21
amf-peer 2 ip 10.251.1.22
ntp-service unicast-server 172.17.0.10
snmp-agent target-host trap address udp-domain 172.17.0.20
info-center loghost 172.17.0.30
#
user-interface vty 0 4
 authentication-mode aaa
 protocol inbound telnet
#
return
END
    return $cfg;
}

sub _bg_cell_status {
    my ( $p, $host ) = @_;
    my $s   = _seed($host);
    my $out = "CellID  PCI   SSB-ARFCN  State   Users\n";
    $out .= sprintf "%-6d  %-4d  %-9d  %-6s  %d\n", $_, ( $s + $_ * 11 ) % 1008, ( 643_296, 650_016, 2_079_167 )[$_], 'UP',
      ( $s >> $_ ) % 300
      for 0 .. 2;
    return $out;
}

# The exact text a device prints for a command, newline-normalised.
sub render {
    my ( $class, $profile, $host, $cmd ) = @_;
    my $gen = $profile->{commands}{$cmd} or return;
    return $gen->( $profile, $host );
}

1;

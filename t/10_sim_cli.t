use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../sim/lib";
use BSSim::CLI;

sub run_cli {
    my ( $cli, @inputs ) = @_;
    my $out = $cli->start;
    $out .= $cli->feed($_) for @inputs;
    $out =~ s/\r//g;
    return $out;
}

subtest 'telnet login, enable and paging' => sub {
    my $cli = BSSim::CLI->new( profile => 'ax4000-r5', hostname => 'T1' );
    my $out = run_cli( $cli, "cbtadmin\r\n", "cbt-pass\r\n", "show running-config\r\n" );
    like $out, qr/Username: Password: \nT1>/, 'logged in to user mode';
    like $out, qr/requires privileged mode/, 'running-config needs enable';

    $out = join "", map { $cli->feed($_) } "enable\r\n", "cbt-enable\r\n", "show running-config\r\n";
    $out =~ s/\r//g;
    like $out, qr/T1#/, 'enable mode prompt';
    like $out, qr/--More--\s*$/, 'output is paged until paging is disabled';
    $out = $cli->feed('q');
    like $out, qr/T1#$/, 'q aborts the pager';
};

subtest 'wrong password is rejected and disconnects after 3 tries' => sub {
    my $cli = BSSim::CLI->new( profile => 'bg7-v200', hostname => 'G1' );
    my $out = run_cli( $cli, map { ( "cbtadmin\n", "nope\n" ) } 1 .. 3 );
    like $out, qr/Authentication failed\. Too many attempts/, 'locked out';
    ok $cli->closed, 'session closed';
};

subtest 'pager command differs per software version' => sub {
    my $r6 = BSSim::CLI->new( profile => 'ax4000-r6', hostname => 'O1', preauth => 1 );
    my $out = run_cli( $r6, "terminal length 0\n", "terminal pager disable\n" );
    like $out, qr/% Unknown command: "terminal length 0"/, 'R5 pager command rejected on R6';
    unlike $out, qr/Unknown command: "terminal pager disable"/, 'R6 pager command accepted';
};

subtest 'preauth (SSH) sessions start at the prompt' => sub {
    my $cli = BSSim::CLI->new( profile => 'bg7-v200', hostname => 'G1', preauth => 1 );
    like run_cli($cli), qr/<G1>$/, 'no login prompt';
};

done_testing;

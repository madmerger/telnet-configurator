use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use CBT::Inventory;

my $dir = tempdir( CLEANUP => 1 );

sub inv {
    my ($text) = @_;
    my $file = "$dir/inv.conf";
    open my $fh, '>', $file or die $!;
    print $fh $text;
    close $fh;
    return $file;
}

my $base = "host = 127.0.0.1\nmodel = AX-4000\nsw = R5.2.1\n";

subtest 'protocol defaults to telnet' => sub {
    my $d = CBT::Inventory->load( inv("[A]\n$base") )->[0];
    is $d->{protocol}, 'telnet', 'default protocol';
    ok !exists $d->{auth}, 'no auth for telnet';
};

subtest 'ssh with password and key auth, secrets from the environment' => sub {
    local $ENV{CBT_T_PASSWORD} = 's3cret';
    local $ENV{CBT_T_KEY}      = '/path/to/id_ed25519';
    my $devs = CBT::Inventory->load(
        inv(    "[P]\n${base}protocol = SSH\npassword = \${CBT_T_PASSWORD}\n"
              . "[K]\n${base}protocol = ssh\nauth = key\nkey_file = \${CBT_T_KEY}\n" )
    );
    is_deeply [ @{ $devs->[0] }{qw(protocol auth password)} ], [ 'ssh', 'password', 's3cret' ], 'password auth is the default';
    is_deeply [ @{ $devs->[1] }{qw(protocol auth key_file)} ], [ 'ssh', 'key', '/path/to/id_ed25519' ], 'key auth';
};

subtest 'invalid settings are rejected' => sub {
    eval { CBT::Inventory->load( inv("[A]\n${base}protocol = rlogin\n") ) };
    like $@, qr/\[A\]: protocol must be telnet or ssh/, 'unknown protocol';
    eval { CBT::Inventory->load( inv("[A]\n${base}protocol = ssh\nauth = hostbased\n") ) };
    like $@, qr/\[A\]: auth must be password or key/, 'unknown auth';
    eval { CBT::Inventory->load( inv("[A]\n${base}protocol = ssh\nauth = key\n") ) };
    like $@, qr/\[A\]: auth = key needs key_file/, 'key auth without key_file';
};

done_testing;

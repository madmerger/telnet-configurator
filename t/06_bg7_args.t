# The standalone BG-7 collector parses options only before HOST PORT USER PASSWORD OUTFILE,
# so a password starting with '-' is passed through as a positional argument.
use strict;
use warnings;
use Test::More;
use FindBin;
use IPC::Open3;
use lib "$FindBin::Bin/lib";
use TestLab qw(root);

my $script = root() . '/collectors/bg7_v200.pl';

sub run_bg7 {
    my $pid = open3( my $in, my $out, undef, $^X, $script, @_ );    # no shell: paths may contain spaces
    close $in;
    my $output = do { local $/; <$out> };
    waitpid $pid, 0;
    return $output // '';
}

for my $args ( [ '--protocol', 'bogus', '--', 'h', '1', 'u', '-secret', '/dev/null' ],
               [ '--protocol', 'bogus', 'h', '1', 'u', '-secret', '/dev/null' ] ) {
    my $err = run_bg7(@$args);
    unlike $err, qr/Unknown option|usage:/, "@$args: password not taken as an option";
    like $err, qr/unknown protocol 'bogus'/, "@$args: positional arguments accepted";
}

like run_bg7( 'h', '1', 'u', 'p', '/dev/null', '--protocol', 'ssh' ), qr/usage:/,
  'options after OUTFILE are rejected instead of silently ignored';

done_testing;

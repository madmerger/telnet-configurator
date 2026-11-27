# The standalone BG-7 collector parses options only before HOST PORT USER PASSWORD OUTFILE,
# so a password starting with '-' is passed through as a positional argument.
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestLab qw(root);

my $script = root() . '/collectors/bg7_v200.pl';
for my $args ( [ '--protocol', 'bogus', '--', 'h', '1', 'u', '-secret', '/dev/null' ],
               [ '--protocol', 'bogus', 'h', '1', 'u', '-secret', '/dev/null' ] ) {
    my $err = qx{$^X $script @$args 2>&1};
    unlike $err, qr/Unknown option|usage:/, "@$args: password not taken as an option";
    like $err, qr/unknown protocol 'bogus'/, "@$args: positional arguments accepted";
}

done_testing;

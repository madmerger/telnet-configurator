package CBT::Collector::AX4000_R5;
# Hoshi Networks AX-4000 eNodeB, software R5.x
use strict;
use warnings;
use parent 'CBT::Collector::Base';

sub prompt     { '/[\w.-]+[>#] ?$/' }
sub enable_cmd { 'enable' }
sub paging_cmd { 'terminal length 0' }
sub commands   { ( 'show version', 'show running-config', 'show cell status' ) }

1;

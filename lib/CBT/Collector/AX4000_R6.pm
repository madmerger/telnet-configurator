package CBT::Collector::AX4000_R6;
# Hoshi Networks AX-4000 eNodeB, software R6.x
# R6 changed the prompt to HOST[R6]# and renamed the pager command.
use strict;
use warnings;
use parent 'CBT::Collector::AX4000_R5';

sub prompt     { '/[\w.-]+\[R6\][>#] ?$/' }
sub paging_cmd { 'terminal pager disable' }

1;


use strict;
use Test::More tests => 2;

$ENV{ZOIDREF} = { settings => { data_dirs => ['.', './t'] }};

use_ok('Zoidberg::Utils', qw/read_data_file/);

my $ref = read_data_file('test');

ok($$ref{ack} eq 'syn', 'read_data_file seems to work');

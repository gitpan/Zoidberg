
use strict;

print "1..17\n";

$ENV{PATH} = './blib/';
$ENV{OK8} = 'ok 8';
$ENV{OK} = 'ok';
$ENV{ARRAY} = join ':', qw/f00 ok b4r/;

$SIG{PIPE} = 'IGNORE';

$|++;
my $zoid = 
	'| blib/script/zoid '
	. ($ENV{DEBUG_ZOID} ? '-D ' : '')
	. '-o data_dirs=./blib/share -o cache_dir=./blib/cache --rcfile=./t/zoidrc';

open ZOID, $zoid;

print ZOID '{ print qq/ok 1 - perl from stdin\n/ }', "\n"; # 1
print ZOID '{ for (1..3) { print q/ok /.($_+1)." - something $_\n" } }', "\n"; # 2..4
print ZOID "blib/echo ok 5 - executable file\n"; # 5
print ZOID "echo ok 6 - executable in path\n"; # 6
print ZOID "test 7 - rcfile with alias\n"; # 7
print ZOID "echo \$OK8 - parameter expansion\n"; # 8
print ZOID "echo \$ARRAY[1] 9 - parameter expansion array style\n"; # 9
print ZOID "echo 'ok' 10 - quote removal\n"; # 10
print ZOID "echo \"\$OK\" 11 - parameter expansion between double quotes\n"; # 11
print ZOID "echo ok 12 - redirection > blib/test12; cat blib/test12\n"; # 12
print ZOID "TEST='ok 13 - local environment' { print(\$TEST, \"\\n\") }\n"; # 13
print ZOID "false && echo 'not ok 14 - logic 2' || echo 'ok 14 - logic 2'\n"; #14
print ZOID
	'{ for (qw/15 a 16 b 17 c/) { print "$_\n" } } | {/\d/}g | {chomp; $_ = "ok $_ - switches $_\n"}p',
	"\n"; # 15..17
#print ZOID 'echo ok 18 - bg process &'; # 18

#print ZOID "test 18 - rcfile with alias\n"; # 18
# FIXME FIXME FIXME - this should work


# TODO much more tests :)

close ZOID;


use strict;

print "1..22\n";

chdir './blib';

unlink 'test12~' or warn 'could not remove test12~' if -e 'test12~';

$ENV{PATH} = ($] < 5.008) ? '.:'.$ENV{PATH} : '.'; # perl 5.6.2 uses shell more extensively
$ENV{OK8} = 'ok 8';
$ENV{OK} = 'ok';
$ENV{ARRAY} = join ':', qw/f00 ok b4r/;

$SIG{PIPE} = 'IGNORE';

$|++;
my $zoid = '| script/zoid -o data_dirs=share -o rcfiles=../t/zoidrc';

open ZOID, $zoid;

print ZOID '{ print qq/ok 1 - perl from stdin\n/ }', "\n"; # 1
print ZOID '{ for (1..3) { print q/ok /.($_+1)." - something $_\n" } }', "\n"; # 2..4
print ZOID "./echo ok 5 - executable file\n"; # 5
print ZOID "echo ok 6 - executable in path\n"; # 6
print ZOID "test 7 - rcfile with alias\n"; # 7
print ZOID "echo \$OK8 - parameter expansion\n"; # 8
print ZOID "echo \$ARRAY[1] 9 - parameter expansion array style\n"; # 9
print ZOID "echo 'ok' 10 - quote removal\n"; # 10
print ZOID "echo \"\$OK\" 11 - parameter expansion between double quotes\n"; # 11
print ZOID "echo ok 12 - redirection 2> test12~ 1>&2; cat test12~\n"; # 12
print ZOID "TEST='ok 13 - local environment' { print(\$TEST, \"\\n\") }\n"; # 13
print ZOID "false && echo 'not ok 14 - logic 2' || echo 'ok 14 - logic 2'\n"; #14
print ZOID "      && echo 'ok 15 - empty command'\n"; # 15
print ZOID "(false || false) || echo 'ok 16 - subshell 1'\n"; # 16
print ZOID "(true  || false) && echo 'ok 17 - subshell 2'\n"; # 17
print ZOID "print '#', <*>, qq#\\n# && print qq#ok 18 - globs aint redirections\\n#\n"; # 18
#print ZOID "echo ok 19 - some quoting >> quote\\ \\'n\\ test; cat 'quote \\'n test'\n"; # 19
print ZOID "echo ok 19 - skipped\n";
print ZOID
	'{ for (qw/20 a b 21 c d 22/) { print "$_\n" } } | {/\d/}g | {chomp; $_ = "ok $_ - switches $_\n"}p',
	"\n"; # 20..22
#print ZOID "test 23 - next after pipeline\n"; # 23

# TODO much more tests :)

close ZOID;


use strict;

print "1..12\n";
#print "ok $_\n" for (1..12);exit 0;

$ENV{PATH} = './t/';
$ENV{OK8} = 'ok 8';
$ENV{OK} = 'ok';
$ENV{ARRAY} = join ':', qw/f00 ok b4r/;

$|++;
open ZOID, '|-', 'bin/zoid', 
	'--data-dirs=./share',
	'--cache-dir=./t/cache',
	'--rcfile=./t/zoidrc';

print ZOID '{ print qq/ok 1 - perl from stdin\n/ }', "\n"; # 1
print ZOID '{ for (1..3) { print q/ok /.($_+1)." - something $_\n" } }', "\n"; # 2..4
print ZOID "t/echo ok 5 - executable file\n"; # 5
print ZOID "echo ok 6 - executable in path\n"; # 6
print ZOID "test 7 - rcfile with alias\n"; # 7
print ZOID "echo \$OK8 - parameter expansion\n"; # 8
print ZOID "echo \$ARRAY[1] 9 - parameter expansion array style\n"; # 9
print ZOID
	'for (qw/10 a 11 b 12 c/) { print "$_\n" } | {/\d/}g | {chomp; $_ = "ok $_ - switches $_\n"}p',
	"\n"; # 10..12

#print ZOID "test 10 - rcfile with alias\n"; # 10
# FIXME FIXME FIXME - this should work

#print ZOID "echo 'ok' X - quote removal\n"; # X
#print ZOID qq#echo "$OK" X - parameter expansion between double quotes\n#; # X

# TODO much more tests :)

close ZOID;

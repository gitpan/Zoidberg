
print "1..9\n";

mkdir 't/var' || die $!;
$ENV{PATH} = './t/';

$|++;
open ZOID, '|-', 'bin/zoid', 
	'--plugin-dirs=./share/skel/plugins/',
	'--data-dirs=./share/skel/',
	'--var-dir=./t/var',
	'--rcfile=./t/zoidrc';

print ZOID '{ print qq/ok 1 - perl from stdin\n/ }', "\n";	# 1
print ZOID '{ for (1..3) { print q/ok /.($_+1)." - something $_\n" } }', "\n"; # 2..4
print ZOID "t/echo ok 5 - executable file\n"; # 5
print ZOID "echo ok 6 - executable in path\n"; # 6
print ZOID 
	'for (qw/7 a 8 b 9 c/) { print "$_\n" } | {/\d/}g | {chomp; $_ = "ok $_ - switches $_\n"}p',
	"\n"; # 7..9

#print ZOID "test 10 - rcfile with alias\n"; # 10
# FIXME FIXME FIXME - this test should work

# TODO much more tests :)

close ZOID;

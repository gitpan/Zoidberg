
require 'm/Makefile.pm';
import Makefile qw/path_copy rmdir_force/;

use Test::Harness;

my $make = Makefile->new;

unshift @INC, 'b/lib', 'b/inc';

my $done = 0;

if (-f 'b/test.pl') {
	print "Going to run test.pl";
	do 'b/test.pl';
	$done = 1;
}

if (-d 'b/t') {
	opendir T, 'b/t';
	my @tests = sort grep {-f 'b/t/'.$_ && m/\.t$/} readdir T;
	closedir T;

	# print "Going to run tests: ".join(', ', @tests)."\n";

	$Test::Harness::verbose = $make->{vars}{TEST_VERBOSE} || $make->{vars}{VERBOSE};
	runtests(map {'b/t/'.$_} @tests);
	$done = 1;
}

unless ($done) { print "No tests defined.\n" } 

__END__


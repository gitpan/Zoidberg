
require 'm/Makefile.pm';
import Makefile qw/path_copy rmdir_force/;

use Test::Harness;

my $make = Makefile->new;

my $done = 0;

chdir 'b/';

unshift @INC, './lib', './inc';

if (-f 'test.pl') {
	print "Going to run test.pl";
	do 'test.pl';
	$done = 1;
}

if (-d 't/') {
	opendir T, 't/';
	my @tests = sort grep {-f 't/'.$_ && m/\.t$/} readdir T;
	closedir T;

	$Test::Harness::verbose = $make->{vars}{TEST_VERBOSE} || $make->{vars}{VERBOSE};
	runtests(map {'t/'.$_} @tests);
	$done = 1;
}

unless ($done) { print "No tests defined.\n" } 

chdir '..';

__END__


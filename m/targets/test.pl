
require 'm/Makefile.pm';
import Makefile qw/path_copy rmdir_force/;

my $make = Makefile->new;

chdir 'b';

unshift @INC, 'lib';

my $done = 0;

if (-f 'test.pl') {
	open IN, 'b/test.pl' || die $!;
	my @cont = (<IN>);
	close IN;

	print "Going to run test.pl";
	$make->print_log("Going to run test.pl", "MESS");

	eval join('\n', @cont);
	if ($@) { die  $@ };
	$done = 1;
}

if (-d 't') {
	opendir T, 't';
	my @tests = grep {-f 't/'.$_ && m/\.t$/} readdir T;
	closedir T;

	print "Going to run tests: ".join(' ', @tests)."\n";
	$make->print_log("Going to run tests: ".join(' ', @tests), "MESS");

	use Test::Harness;
	$Test::Harness::verbose = $make->{vars}{TEST_VERBOSE} || $make->{vars}{VERBOSE};
	if (runtests(map {'t/'.$_} @tests)) { $make->print_log("Tests ok", 'check'); }
	else { $make->print_log("Tests failed", 'error'); }

	$done = 1;
}

chdir '..';

unless ($done) { 
	print "No tests defined.\n";
	$make->print_log("No tests defined.", "MESS");
}

__END__

=head1 NAME

test

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

If there is a F<test.pl>, the contents are evalled.

If there is a directory F<t> all files in this dir with extension ".t"
are run using L<Test::Harness>.

=head1 VARS

If TEST_VERBOSE or VERBOSE are set Test::Harness is set verbose.

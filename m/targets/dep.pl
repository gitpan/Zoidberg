
require 'm/Makefile.pm';
import Makefile qw/get_version compare_version/;

eval('use CPAN;'); # somehow I need to force this to be evalled on run time _after_ the require m/Makefile.pm !!???
if ($@) { die "Is it possible you don't have CPAN installed? You might want to do this first."}
$CPAN::Config->{term_is_latin} = 1; # just to be sure

my $make = Makefile->new;

unless (exists $make->{include}{PREREQ_PM}) {die "No include PREREQ_PM found";}

my $dep_ok = 1;

while (my ($module, $version) = each %{$make->{include}{PREREQ_PM}}) {
	my $our_v = get_version($module);
	if ($make->{vars}{VERBOSE}) { print "checking $module version $version we have: ".$our_v."\n"; }
	if (compare_version($version, $our_v) < 0){
		$dep_ok = 0;
		print "Missing dependency \"$module\"".($version ? " version $version\n" : "\n")."Going to try CPAN\n";
		$make->print_log($module, 'CPAN');
		unless (install($module)) { $make->print_log("install ".$module." from CPAN failed", 'ERROR'); }
	}
}

if ($dep_ok) { 
	print "Dependencies seem to be ok -- no need to use CPAN.\n"; 
	$make->print_log("Dependencies seem up to date.", "CHECK");
}
else { print "done.\n"; }

__END__

=head1 NAME

dep

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

This target tries to fetch missing dependencies from CPAN.
It's wise to config your CPAN first.
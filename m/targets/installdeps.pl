
require 'm/Makefile.pm';
import Makefile qw/get_version compare_version/;

eval('use CPAN;'); # somehow I need to force this to be evalled on run time _after_ the require m/Makefile.pm !!???
if ($@) { die "Is it possible you don't have CPAN installed? You might want to do this first."}
$CPAN::Config->{term_is_latin} = 1; # just to be sure

my $make = Makefile->new;

unless (exists $make->{include}{PREREQ_PM}) {die "No include PREREQ_PM found";}

my $dep_ok = 1;

while (my ($module, $version) = each %{$make->{include}{PREREQ_PM}}) {
	print "checking $module version $version we have: ".get_version($module)."\n" if $make->{vars}{VERBOSE};
	unless ( check_installed($module, $version) ) {
		$dep_ok = 0;
		print "Missing dependency \"$module\"".($version ? " version $version\n" : "\n")."Going to try CPAN\n";
		install($module);
		print "install ".$module." from CPAN failed\n" unless check_installed($module, $version);
	}
}

if ($dep_ok) { 	print "Dependencies seem to be up to date.\n" }
else { print "done.\n"; }

sub check_installed {
	my ($module, $version) = @_;
	my $our_v = get_version($module);
	return (!defined $our_v || compare_version($version, $our_v) < 0) ? 0 : 1;
}

__END__


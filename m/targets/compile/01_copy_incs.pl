
require 'm/Makefile.pm';
import Makefile qw/path_copy get_version get_version_from compare_version/;

my $make = Makefile->new;

mkdir 'b' unless -d 'b';
#mkdir 'b/inc' unless -d 'b/inc';

foreach my $file (grep m{^(\./)?inc/}, $make->manifest) {
	next unless $file =~ m{\.(pl|pm)$}i; # FIXME what to do with pod / txt
	$file =~ m{^(?:\./)?inc/(.*)};
	my $inst_version = get_version($1);
	my $version = get_version_from($file);
	if (defined $inst_version && compare_version($version, $inst_version) >= 0) {
		print "$file skipped, is allready installed\n" if $make->{vars}{VERBOSE};
		next;
	}
	print "copying $file\n" if $make->{vars}{VERBOSE};
	path_copy($file, 'b/'.$file);
}


__END__



require 'm/Makefile.pm';
import Makefile qw/path_copy/;

my $make = Makefile->new;

for ($make->manifest) {
	if (m/^(\.\/)?(share|etc|t)\// || !m{/}) {
		my $file = $_;
		if ($make->{vars}{VERBOSE}) { print "copying $file\n"; }
		path_copy($file, 'b/'.$file);
		if (-x $file) { chmod 0755, 'b/'.$file; }
	}
}


__END__


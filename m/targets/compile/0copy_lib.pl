
require 'm/Makefile.pm';
import Makefile qw/path_copy rmdir_force/;

my $make = Makefile->new;

unless (-d 'b') {
    mkdir 'b';
}

print "Copying files to build directory.\n";

for ($make->manifest) {
	if (m/^(\.\/)?lib\//) {
		if ($make->{vars}{VERBOSE}) { print "copying $_\n"; }
		path_copy($_, 'b/'.$_);
	}
}


__END__

=head1 NAME

compile libs

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

Copy files in F<./lib> to the build directory

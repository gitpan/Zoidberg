
require 'm/Makefile.pm';
import Makefile qw/file_copy/;

use Pod::Man;

my $make = Makefile->new;

print "Creating man pages.\n";

my @manifest = $make->manifest;
my $version = $make->{include}{VERSION} || undef;

# parse .pod man pages
foreach my $section (0..9) {
	unless (-d "man".$section) { next; }
	unless (-d "b/man".$section) { mkdir "b/man".$section; }

	my $parser = Pod::Man->new (release => $version, section => $section);

	for (grep {m/^(?:\.\/)?man$section\//} @manifest) {
		my $file = $_;
		if ($file =~ s/(\.pod)$//i) {
			if ($make->{vars}{VERBOSE}) { print "Manifying $file$1\n"; }
			$parser->parse_from_file ($file.$1, 'b/'.$file.'.'.$section);
		}
		else {
			if ($make->{vars}{VERBOSE}) { print "Copying $file\n"; }
			file_copy($file, 'b/'.$file);
		}
	}
}

# parse module pods

my $parser = Pod::Man->new (release => $version, section => 3);
unless (-d "b/man3") { mkdir "b/man3"; }

for (grep {m/^(?:\.\/)?lib\/.*?\.(pm|pod)$/i} @manifest) {
	my $file = $_;
	my $name = $file;
	$name =~ s/\.(pod|pm)$//i;
	$name =~ s/^(?:\.\/)?lib\///;
	$name =~ s/\//\:\:/g;
	if ($make->{vars}{VERBOSE}) { print "Manifying $file\n"; }
	$parser->parse_from_file ($file, 'b/man3/'.$name.'.3');
}


__END__

=head1 NAME

compile man pages

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

Generates man pages out pod by using Pod::Man.

Searches F<./man(0..9)> for .pod files (just copies all other files found) and places these
in F<b/man(0..9).

Scans F<./lib> for .pm and .pod files and puts these in F<b/man3>.

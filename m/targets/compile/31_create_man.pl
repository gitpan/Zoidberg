
require 'm/Makefile.pm';
import Makefile qw/file_copy/;

use Pod::Man;

my $make = Makefile->new;

print "Creating man pages.\n";

my @manifest = $make->manifest;
my $version = $make->{include}{VERSION} || undef;

# parse .pod man pages
foreach my $section (1..9) {
	unless (-d "man".$section) { next; }
	unless (-d "b/man".$section) { mkdir "b/man".$section; }

	my $parser = Pod::Man->new(
		release => "Zoidberg $version", 
		section => $section,
		center => '');

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

my $parser = Pod::Man->new(
	release => "Zoidberg $version", 
	section => 3);
	
unless (-d "b/man3") { mkdir "b/man3"; }

for (grep {m/^(?:\.\/)?lib\/.*?\.(pm|pod)$/i} @manifest) {
	my $file = $_;
	my $name = $file;
	$name =~ s/\.(pod|pm)$//i;
	$name =~ s/^(?:\.\/)?lib\///;
	$name =~ s/\//\:\:/g;
	if ($make->{vars}{VERBOSE}) { print "Manifying $file\n"; }
	$parser->parse_from_file ($file, 'b/man3/'.$name.'.3pm');
}


__END__

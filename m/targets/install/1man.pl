
require 'm/Makefile.pm';
import Makefile qw/path_copy/;

my $make = Makefile->new;

use Config;

foreach my $section (0..9) {
	unless (-d 'b/man'.$section) { next; }
	my $to = $make->{vars}{'INSTALLMAN'.$section.'DIR'} || $Config{'installman'.$section.'dir'};
	$to =~ s/\/$//; #/
	unless ($to) {
		print "==> No install dir found for man$section man pages\n";
		print "==> You should supply a var INSTALLMAN".$section."DIR\n";
		next;
	}

	print "Installing section $section man pages to $to\n";

	opendir M, 'b/man'.$section;
	my @files = grep {$_ !~ m/^\.\.?$/} readdir M;
	closedir M;

	for (@files) {
		if ($make->{vars}{VERBOSE}) { print "copying man man$section/$_ to $to/$_\n"; }
		$make->print_log($to.'/'.$_, 'installed');
		path_copy('b/man'.$section.'/'.$_, $to.'/'.$_);
	}
}


__END__


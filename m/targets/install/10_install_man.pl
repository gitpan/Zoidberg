
require 'm/Makefile.pm';
import Makefile qw/dir_copy/;

my $make = Makefile->new;

use Config;

foreach my $section (0..9) {
	unless (-d 'b/man'.$section) { next; }
	my $to;
	if ($make->{vars}{MAN_DIR}) { $to = $make->{vars}{MAN_DIR} . '/man' . $section }
	elsif ($Config{'installman'.$section.'dir'}) { $to = $Config{'installman'.$section.'dir'} }
	else { die 'Please specify MAN_DIR' }
	$to =~ s/\/$//; #/

	print "Installing section $section man pages to $to\n";

	open LOG, '>>'.$make->{vars}{INSTALL_LOG} 
		|| die "Could not open log file\n"
		if $make->{vars}{INSTALL_LOG};

	for (dir_copy('b/man'.$section, $to)) { print LOG $to, '/', $_, "\n"	}

	close LOG
		|| die "Could not write log file\n"
		if $make->{vars}{INSTALL_LOG};
}


__END__



require 'm/Makefile.pm';

my $make = new Makefile;

open LOG, '>'.$make->{vars}{INSTALL_LOG}
	|| die "Could not open log file\n"
	if $make->{vars}{INSTALL_LOG};
		
for (qw/APPDIR PREFIX CONFIG LIB_DIR MAN_DIR/) {
	next unless $make->{vars}{$_};
	unless (-d $make->{vars}{$_}) {
		print "Creating dir: $make->{vars}{$_}\n" if $make->{vars}{VERBOSE};
		mkdir $make->{vars}{$_} || die "Could not create dir $make->{vars}{$_}\n";
		print LOG $make->{vars}{$_}, "\n" if $make->{vars}{INSTALL_LOG};
	}
}
close LOG 
	|| die "Could not write to log file\n"
	if $make->{vars}{INSTALL_LOG};


require 'm/Makefile.pm';

my $make = new Makefile;

for (qw/APPDIR PREFIX CONFIG LIB_DIR MAN_DIR/) {
	next unless $make->{vars}{$_};
	mkdir $make->{vars}{$_} 
		|| die "Could not create dir $make->{vars}{$_}\n"
		unless -d $make->{vars}{$_};
}

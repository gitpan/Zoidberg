
require 'm/Makefile.pm';

my $make = Makefile->new;

$|++;

die "No log file found, can't uninstall :( try specifying 'INSTALL_LOG'\n" 
	unless $make->{vars}{INSTALL_LOG} && -s $make->{vars}{INSTALL_LOG}; 

print "Going to remove $make->{include}{NAME}.\nPress Ctrl-C NOW if you're not sure.\n";
for (0..4) {
	print 5 - $_;
	sleep 1;
}
print "\nOk, here we go ...\n\n";

open IN, $make->{vars}{INSTALL_LOG} || die "Could not read log file\n";
while (<IN>) {
	chomp;
	unless (/^\s*#/) {
		next unless -e $_;
		unlink $_ || die $!;
		print "Deleted $_\n";
	}
}
close IN;

print "Done\n";

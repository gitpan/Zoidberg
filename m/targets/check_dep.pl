
require 'm/Makefile.pm';

my $make = Makefile->new;

$make->check_dep || print "==> Try \"make dep\" to fetch missing modules from CPAN.\n";

__END__



require 'm/Makefile.pm';

my $make = Makefile->new;

$make->{vars}{CONFIG} =~ s/\/$//; #/
$make->{vars}{PREFIX} =~ s/\/$//; #/

my %conf = (
	'test'		=> q{'123'},
);

if ($make->{vars}{PERS_DIR}) { $conf{config_dir} = "'".$make->{vars}{PERS_DIR}."'"; }

unshift @INC, './b/lib/';
eval q{use Zoidberg::Config};
Zoidberg::Config->mutate(\%conf, 'b/lib/Zoidberg/Config.pm');

print "Config mutated.\n";

__END__


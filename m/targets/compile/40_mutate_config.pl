
require 'm/Makefile.pm';

my $make = Makefile->new;

# $make->{vars}{CONFIG} =~ s/\/$//; #/
$make->{vars}{PREFIX} =~ s/\/$//; #/

my %conf = ( prefix => "'".$make->{vars}{PREFIX}."'" );


#if ($make->{vars}{CONF_DIR}) { 
#	$conf{config_dir} = "'".$make->{vars}{CONF_DIR}."'";
#	$conf{plugins_dir} = "'".$make->{vars}{CONF_DIR}."plugins/'"
#}

unshift @INC, './b/lib/';
eval q{use Zoidberg::Config};
Zoidberg::Config->mutate(\%conf, 'b/lib/Zoidberg/Config.pm');

print "Config mutated.\n";

__END__


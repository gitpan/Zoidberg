
require 'm/Makefile.pm';
import Makefile qw/path_copy/;

use Config;

my $make = Makefile->new;

my $lib_dir = $make->{vars}{LIB_DIR} || $make->{vars}{LIB};
# LIB added after reading cpan docs for campatibility

my %var_names = (
	perl => 'installprivlib',
	site => 'installsitelib',
	vendor => 'installvendorlib'
);

unless ($lib_dir) {
	my $set = $make->{vars}{INSTALLDIRS} || die "Please specify INSTALLDIRS or LIB_DIR";
	my $conf_var = $var_names{$set} 
		|| die "INSTALLDIRS has a invalid value, should be: 'perl', 'site' or 'vendor'";
	$lib_dir = $Config{$conf_var};
}

$lib_dir =~ s/\/$//; #/

unless ($lib_dir) { die "can't find a place to install libs"; }

print "Installing libs to $lib_dir\n";

open LOG, '>>'.$make->{vars}{INSTALL_LOG} 
	|| die "Could not open log file\n"
	if $make->{vars}{INSTALL_LOG};
	
for ($make->manifest) {
	if (m/^(?:\.\/)?(?:lib|inc)\/(.*)$/) {
		eval { path_copy('b/'.$_, $lib_dir.'/'.$1) };
		print LOG qq($lib_dir/$1\n) unless $@;
	}
}

close LOG
	|| die "Could not write log file\n"
        if $make->{vars}{INSTALL_LOG};



require 'm/Makefile.pm';
import Makefile qw/path_copy/;

my $make = Makefile->new;

my $lib_prefix = $make->{vars}{LIB_PREFIX} || $make->{vars}{LIB}; 

unless ($lib_prefix) {
	use Config;
	my $set = $make->{vars}{INSTALLDIRS} || die "Please specify INSTALLDIRS or LIB_PREFIX";
	my $conf_var = '';
	if ($set eq 'perl') { $conf_var = 'installprivlib';}
	elsif ($set eq 'site') { $conf_var = 'installsitelib';}
	elsif ($set eq 'vendor') { $conf_var = 'installvendorlib';}
	else { die "INSTALLDIRS has a invalid value"; }
	$lib_prefix = $Config{$conf_var};
}

$lib_prefix =~ s/\/$//; #/

unless ($lib_prefix) { die "can't find a place to install libs"; }

print "Installing libs to $lib_prefix\n";

for ($make->manifest) {
	if (m/^(?:\.\/)?lib\/(.*)$/) {
		path_copy('b/'.$_, $lib_prefix.'/'.$1);
		$make->print_log($lib_prefix.'/'.$1, 'installed');
	}
}


__END__

=head1 NAME

install libs

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

Install all files in the F<./lib> dir.

=head1 VARS

If LIB_PREFIX or LIB is specified libs will be installed to this dir.
Else if INSTALLDIRS is one of "perl", "site" or "vendor" the apropriate 
dir is used from %Config.

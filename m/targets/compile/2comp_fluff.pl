
require 'm/Makefile.pm';

my $make = Makefile->new;

print "Creating script zoid.\n";

mkdir 'b/bin' || die $!;

$make->{vars}{CONFIG} =~ s/\/$//; #/
$make->{vars}{PREFIX} =~ s/\/$//; #/

my %conf = (
	'prefix'	=> "'".$make->{vars}{PREFIX}."/'",	# prefix to zoidberg files
	'skel_dir'	=> "'".$make->{vars}{CONFIG}."/zoid/'",	# path to default config file
	'dir'		=> "\$passwd[7].'/.zoid/'",		# users personal dir
	'my_inc'	=> "()",
);

if ($make->{vars}{PERS_DIR}) { $conf{dir} = "'".$make->{vars}{PERS_DIR}."'"; }
if ($make->{vars}{LIB_PREFIX}) { $conf{my_inc} = "('".$make->{vars}{LIB_PREFIX}."')"; }

open IN, 'bin/fluff' || die $!;
open OUT, '>b/bin/zoid'  || die $!;

my $_c = 0;
while (<IN>) {
	if (/#### CONFIG ####/) { $_c++ }
	if ($_c) {
		if (/#### END ####/) { $_c-- }
		elsif (/^\s*my\s+([\$\@\%])(.*?)\s/) {
			$_ = "my $1$2 = ".$conf{$2}.";\n";
		}
	}
	print OUT $_;
}

close OUT;
close IN;

chmod 0755, "b/bin/zoid";


__END__

=head1 NAME

compile fluff (ie zoid)

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

Zoidberg specific, generates F<b/bin/zoid> out F<bin/fluff>

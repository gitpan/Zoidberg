
require 'm/Makefile.pm';
import Makefile qw/path_copy/;

my $make = Makefile->new;

foreach my $file ($make->manifest) {
	if ($file =~ m/^(\.\/)?(bin|doc|share|etc|t)\//) {
		if ($make->{vars}{VERBOSE}) { print "copying $file\n"; }
		path_copy($file, 'b/'.$file);
		if (-x $file) { chmod 0755, 'b/'.$file; }
	}
}

foreach my $file (qw/README Changes Install BUGS TODO/) {
	if ($make->{vars}{VERBOSE}) { print "copying $file\n"; }
	path_copy($file, 'b/doc/'.$file);
}

rename 'b/bin/fluff', 'b/bin/zoid' || die $!;
chmod 0755, 'b/bin/zoid';

# set #!

die qq/You don't have perl !? Please set var 'PERL'\n/
	unless $make->{vars}{PERL};

open IN, 'b/bin/zoid' || die "Could not read b/bin/zoid\n";
my @regels = (<IN>);
close IN  || die "Could not read b/bin/zoid\n";

$regels[0] = q/#!/.$make->{vars}{PERL}.qq/\n/;
$regels[1] = q/my $APPDIR = '/.$make->{vars}{APPDIR}.qq/';\n/ if $make->{vars}{APPDIR};

open OUT, '>b/bin/zoid' || die "Could not write b/bin/zoid\n";
print OUT @regels;
close OUT || die "Could not write b/bin/zoid\n";

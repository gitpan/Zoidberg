
require 'm/Makefile.pm';
import Makefile qw/dir_copy/;

my $make = Makefile->new;

$make->{vars}{PREFIX} =~ s/\/$//; #/
$make->{vars}{CONFIG} =~ s/\/$//; #/

chdir 'b';

# bin
print "Installing scripts to  $make->{vars}{PREFIX}/bin/\n";
for (dir_copy('bin', $make->{vars}{PREFIX}.'/bin/')) {
	$make->print_log($make->{vars}{PREFIX}.'/bin/'.$_, 'installed');
	if (-x 'bin/'.$_) { chmod 0775, $make->{vars}{PREFIX}.'/bin/'.$_; }
}

# etc
print "Installing config files to  $make->{vars}{CONFIG}/zoid/\n";
for (dir_copy('etc', $make->{vars}{CONFIG}.'/zoid/')) {
	$make->print_log($make->{vars}{CONFIG}.'/zoid/'.$_, 'installed');
}

# share
print "Installing share files to  $make->{vars}{PREFIX}/share/zoid/\n";
for (dir_copy('share', $make->{vars}{PREFIX}.'/share/zoid/')) {
	$make->print_log($make->{vars}{PREFIX}.'/share/zoid/'.$_, 'installed');
}

#doc
if (-d 'doc') {
	print "Installing doc files to  $make->{vars}{PREFIX}/share/doc/zoid/\n";
	for (dir_copy('doc', $make->{vars}{PREFIX}.'/share/doc/zoid/')) {
		$make->print_log($make->{vars}{PREFIX}.'/share/doc/zoid/'.$_, 'installed');
	}
}

chdir '..';

print "## If all went well, try type \"zoid\" to start the Zoidberg shell.\n";

__END__

=head1 NAME

install files

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

Zoidberg specific, install files

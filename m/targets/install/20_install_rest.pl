
require 'm/Makefile.pm';
import Makefile qw/dir_copy path_copy/;

my $make = Makefile->new;

$make->{vars}{PREFIX} =~ s/\/$//; #/
$make->{vars}{CONFIG} =~ s/\/$//; #/

open LOG, '>>'.$make->{vars}{INSTALL_LOG}
	|| die "Could not open log file\n"
	if $make->{vars}{INSTALL_LOG};

# bin
print "Installing scripts to $make->{vars}{PREFIX}/bin/\n";
for (dir_copy('b/bin', $make->{vars}{PREFIX}.'/bin/')) {
	print LOG $make->{vars}{PREFIX}.'/bin/'.$_."\n";
	chmod 0775, $make->{vars}{PREFIX}.'/bin/'.$_;
}

# etc
print "Installing rc files to $make->{vars}{CONFIG}\n";
for (dir_copy('b/etc', $make->{vars}{CONFIG})) {
	print LOG $make->{vars}{CONFIG}.'/'.$_."\n";
}

# share
print "Installing share files to $make->{vars}{PREFIX}/share/zoid/\n";
unless (-d $make->{vars}{PREFIX}.'/share/') { mkdir $make->{vars}{PREFIX}.'/share/' || die $! }
for (dir_copy('b/share', $make->{vars}{PREFIX}.'/share/zoid/')) {
	print LOG $make->{vars}{PREFIX}.'/share/zoid/'.$_."\n";
}

# doc
print "Installing doc files to $make->{vars}{PREFIX}/doc/zoid/\n";
unless (-d $make->{vars}{PREFIX}.'/doc/') { mkdir $make->{vars}{PREFIX}.'/doc/' || die $! }
for (dir_copy('b/doc', $make->{vars}{PREFIX}.'/doc/zoid/')) {
	print LOG $make->{vars}{PREFIX}.'/doc/zoid/'.$_."\n";
}

# APPDIR
if ($make->{vars}{APPDIR}) {
	for (
		['AppRun',	'bin/zoid'], 
		['.DirIcon',	'share/zoid/pixmaps/zoid64.png'], 
		['AppInfo.xml',	'share/zoid/AppInfo.xml'],
		['Help',	'doc/zoid/']
	) {
		symlink	$make->{vars}{APPDIR}.'/'.$_->[1],
			$make->{vars}{APPDIR}.'/'.$_->[0]
			|| die $!;
		print LOG $make->{vars}{APPDIR}.'/'.$_->[0]."\n";
	}
}

# Wrap up the install log
if ($make->{vars}{INSTALL_LOG}) {
	my $to = $make->{vars}{PREFIX}.q(/share/zoid/install.log);
	print LOG $to."\n";
	close LOG || die "Could not write log file\n";
	path_copy($make->{vars}{INSTALL_LOG}, $to);
}

print "## If all went well, try type \"zoid\" to start the Zoidberg shell.\n";

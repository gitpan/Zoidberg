
use strict;

require 'm/Makefile.pm';
import Makefile qw/dir_copy path_copy/;

my $make = Makefile->new;

open LOG, '>', $make->{vars}{INSTALL_LOG}
	|| die "Could not open log file: $make->{vars}{INSTALL_LOG}\n";

## install files ##

# bin
my $bin_dir = $make->{vars}{BIN_DIR};
print "Installing scripts to $bin_dir\n";
for (dir_copy('b/bin', $bin_dir)) {
	print LOG qq($bin_dir/$_\n);
	chmod 0775, qq($bin_dir/$_);
}

# libs
my $lib_dir = $make->{vars}{LIB_DIR};
print "Installing libs to $lib_dir\n";
for my $d (qw#b/lib b/inc#) {
	print LOG qq($lib_dir/$_\n)
		for dir_copy($d, $lib_dir);
}


# etc, share && doc
for (
	[qw/doc doc/, $make->{vars}{DOC_DIR}],
	[qw/data share/, $make->{vars}{DATA}],
	[qw/rc etc/, $make->{vars}{CONFIG} ],
) {
	my $to = $$_[2];
	print "Installing $$_[0] files to $to\n";
	print LOG qq($to/$_\n)
		for dir_copy("b/$$_[1]", $to);
}

# man pages

foreach my $section (0..9) {
	next unless -d "b/man$section";
	my $to = $make->{vars}{"MAN$section\_DIR"}
		|| $make->{vars}{MAN_DIR}."/man$section";
	die "Please specify MAN_DIR or MAN$section\_DIR" unless $to;
	print "Installing section $section man pages to $to\n";
	print LOG "$to/$_\n"
		for dir_copy("b/man$section", $to);
}

## AppDir ##
if ($make->{vars}{APPDIR}) {
	my $App = $make->{vars}{APPDIR};
	my $can_symlink = eval { symlink("",""); 1 }; # copied from perlfunc
	for (
		['.DirIcon',	'share/pixmaps/zoid64.png'],
		['AppInfo.xml',	'share/AppInfo.xml'],
	) {
		if ($can_symlink) { symlink "$App/$$_[1]", "$App/$$_[0]" }
		else { path_copy("$App/$$_[1]", "$App/$$_[0]") }
		print LOG qq($App/$$_[0]\n);
	}
}

## Wrap up the install log ##
my $to = $make->{vars}{DATA}.'/install.log';
print LOG "$to\n";
close LOG || die "Could not write log file\n";
path_copy($make->{vars}{INSTALL_LOG}, $to);

print "## If all went well, try type \"zoid\" to start the Zoidberg shell.\n";

exit 0;

__END__


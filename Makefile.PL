
# TODO Bootstrap code for Dependencies

require 'm/Makefile.pm';
import Makefile qw/get_version_from pd_read/;

use strict;
use Config;

my %config = (
	'default_target' => 'compile',
	'fake_targets' => [qw/all cpan/],
#	'profile' => 'default',
	'depends' => {
		'test'		=> ['compile'],
		'install'	=> ['compile'],
		'all'		=> [qw/compile test install/],
		'cpan'		=> [qw/compile installdeps test install/],
	},
	'help' => {
		'compile'	=> 'Prepare all files for installation',
		'test'		=> 'Check whether the compiled files work correctly',
		'install'	=> 'Install Zoidberg on your system',
		'all'		=> 'Compile, test, install',
		'checkmanifest'	=> 'Check for missing files',
		'checkdeps'	=> 'Check for missing dependencies',
		'installdeps'	=> 'Fetch missings dependencies from CPAN',
		'cpan'		=> 'Make all and install deps from CPAN',
		'uninstall'	=> 'Given a install log remove all files',
		'clean'		=> 'Clean the source tree to start over'
	},
	'vars' => {
		INSTALL_LOG => 'b/install.log',
		PREFIX   => '/usr/local',
		BIN_DIR  => '',
		LIB_DIR  => '',
		MAN_DIR  => '',
		DOC_DIR  => '',
		DATA     => '',
#		LIB => '', # supported, but not in list
		TEST_VERBOSE => 0,
		VERBOSE => 0,
		PERL => $Config{perl5}
			|| $Config{perlpath} || '/usr/bin/perl',
		CONFIG => '/etc',
		INSTALLDIRS => 'site',
		MAN2HTML => 0,
		APPDIR => '',
	},
	'include' => {
		'NAME'		=> 'Zoidberg',
		'VERSION'	=> get_version_from('lib/Zoidberg.pm'),
		'AUTHOR'	=> 'Jaap G Karssenberg <pardus@cpan.org> and RL Zwart <rlzwart@cpan.org>',
	},
);

my $make = Makefile->new(\%config);

if ($make->{vars}{APPDIR}) { # overrule other settings
	my $App = $make->{vars}{APPDIR};
	for (
		['BIN_DIR',  $App],
		['LIB_DIR',  "$App/lib/"],
		['MAN_DIR',  "$App/Help/"],
		['DOC_DIR',  "$App/Help/"],
		['DATA',     "$App/share/"],
		['MAN2HTML', 1],
	) { $make->{vars}{$$_[0]} ||= $$_[1] }
	$make->{vars}{CONFIG} = "$App/Config/"
		unless $make->{vars}{CONFIG} ne '/etc';
	
}
else {
	my $Pref = $make->{vars}{PREFIX};
	for (
		['BIN_DIR', "$Pref/bin"],
		['DOC_DIR', "$Pref/doc/zoid"],
		['DATA',    "$Pref/share/zoid"],
	) { $make->{vars}{$$_[0]} ||= $$_[1] }

	my %var_names = qw/
		perl	installprivlib
		site	installsitelib
		vendor	installvendorlib
	/;
	$make->{vars}{LIB_DIR} ||= $make->{vars}{LIB}
		|| $Config{$var_names{$make->{vars}{INSTALLDIRS}}};
	# LIB added after reading cpan docs for campatibility

	unless ($make->{vars}{MAN_DIR}) {
		$make->{vars}{MAN1_DIR} ||= "$Pref/man/man1";
		$make->{vars}{MAN3_DIR} ||= $Config{man3dir} || "$Pref/man/man3";
	}
}

# get dependecies from Depends.pd
my $depends = pd_read('m/Depends.pd');

$make->{include}{PREREQ_PM} = $depends->{'core'};

$make->check_manifest;
$make->check_dep || print "==> Try \"make installdeps\" to fetch missing modules from CPAN.\n";
$make->write_makefile;

__END__

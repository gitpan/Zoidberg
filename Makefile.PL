
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
		'all' => [qw/compile test install/],
		'cpan' => [qw/compile installdeps test install/],
		'realclean' => [qw/clean/],
	},
	'help' => {
		'compile' => 'Prepare all files for installation',
		'install' => 'Install Zoidberg on your system',
		'all' => 'Compile, test, install',
		'checkmanifest' => 'Check for missing files',
		'checkdeps' => 'Check for missing dependencies',
		'installdeps' => 'Fetch missings dependencies from CPAN',
		'cpan' => 'Make all and install deps from CPAN',
		'cvs' => 'Try updating source tree from anonymous CVS',
		'update_meta' => 'Update meta data - devel only',
		'release' => 'Create release files - devel only',

	},
	'vars' => {
		'INSTALL_LOG' => 'b/install.log',
		'PREFIX' => '/usr/local',
		'LIB_DIR' => '',
		'MAN_DIR' => '',
		'DOC_DIR' => '', # TODO use this var
#		'LIB' => '', # see install_libs
		'TEST_VERBOSE' => 0,
		'VERBOSE' => 0,
		'PERL' => $Config{perl5}||$Config{perlpath},
		'CONFIG' => '/etc',
		'INSTALLDIRS' => 'site',
		'NO_HTML' => 0,
		'MAN2HTML' => 0,
		'APPDIR' => '',
	},
	'include' => {
		'NAME'		=> 'Zoidberg',
		'VERSION'	=> get_version_from('lib/Zoidberg.pm'),
		'AUTHOR'	=> 'Jaap G Karssenberg <j.g.karssenberg@student.utwente.nl> and RL Zwart <rlzwart@cpan.org>',
	},
);

my $make = Makefile->new(\%config);

# TODO this should only be used in CVS
#unless ($make->{profile} eq 'core') { # core profile is most minimal
#	unless (-f 'manifest.'.$make->{profile}) { die 'No such profile.' }
#	else { print 'Using profile: '.$make->{profile}."\n" }
#	$make->{manifest} = 'MANIFEST.'.$make->{profile};
#	open M, '>'.$make->{manifest} || die $!;
#	open B, 'MANIFEST' || die 'you\'re in the wrong dir'; # base manifest
#	while (<B>) { print M $_ }
#	close B;
#	open E, 'manifest.'.$make->{profile} || die $!; # extra's for this profile
#	while (<E>) { print M $_ }
#	close E;
#	close M;
#}
#else { $make->{manifest} = 'MANIFEST' }

if ($make->{vars}{APPDIR}) { # overrule other settings
	my $ad = $make->{vars}{APPDIR};
	$make->{vars}{PREFIX} = $ad;
	$make->{vars}{CONFIG} = $ad.'/etc/';
	$make->{vars}{LIB_DIR} = $ad.'/lib/';
	$make->{vars}{MAN_DIR} = $ad.'/man/';
	$make->{vars}{CONF_DIR} = $ad.'/conf/';
}

# get dependecies from Depends.pd
my $depends = pd_read('m/Depends.pd');
die qq/"profile" feature has been disabled\n/ if $make->{vars}{profile};
#my $p_depends = {};
#foreach my $ding ('core', $make->{profile}) {
#	map {$p_depends->{$_} = $depends->{$ding}{$_}} keys %{$depends->{$ding}};
#}
#$make->{include}{PREREQ_PM} = $p_depends;
$make->{include}{PREREQ_PM} = $depends->{'core'};

$make->check_manifest;
$make->check_dep || print "==> Try \"make installdeps\" to fetch missing modules from CPAN.\n";
$make->write_makefile;


__END__


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
		'help' => 'print this text',
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
		'PERL5' => $Config{perl5},
#		'CONFIG' => '/etc',
		'INSTALLDIRS' => 'site',
		'NO_HTML' => 0,
		'MAN2HTML' => 0,
	},
	'include' => {
		'NAME'		=> 'Zoidberg',
		'VERSION'	=> get_version_from('lib/Zoidberg.pm'),
		'AUTHOR'	=> 'Jaap G Karssenberg <j.g.karssenberg@student.utwente.nl> and RL Zwart <r.l.zwart@caremail.nl>',
	},
	'help_postamble' =>
"--[ Zoidberg ]

  Use \"make all\" to install Zoidberg

  The LIB_DIR var overloads the INSTALLDIRS var.  
  The place where libraries and man pages are installed is _not_ 
  influenced by PREFIX - use LIB_DIR and MAN_DIR for that.

  try \"perl Makefile.PL LOCAL_DIR=my_dir\" for a private installation

  See also <http://Zoidberg.sourceforge.net>",

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

if ($make->{vars}{LOCAL_DIR}) { # overrule other settings
	$make->{vars}{PREFIX} = $make->{vars}{LOCAL_DIR};
	$make->{vars}{CONFIG} = $make->{vars}{LOCAL_DIR}.'/etc/';
	$make->{vars}{LIB_DIR} = $make->{vars}{LOCAL_DIR}.'/lib/';
	$make->{vars}{MAN_DIR} = $make->{vars}{LOCAL_DIR}.'/man/';
	$make->{vars}{PERS_DIR} = $make->{vars}{LOCAL_DIR}.'/conf';
	for (qw/LOCAL_DIR PREFIX CONFIG LIB_DIR MAN_DIR/) {
		unless (-d $make->{vars}{$_}) { mkdir $make->{vars}{$_}; }
	}
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

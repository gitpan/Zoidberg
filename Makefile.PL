
require 'm/Makefile.pm';
import Makefile qw/get_version_from pd_read/;

use strict;

# get dependecies from Depends.pd
my $depends = pd_read('m/Depends.pd');

my %config = (
	'default_target' => 'compile',
	'log_file' => $ENV{PWD}.'/m/make.log',
	'conf_file' => $ENV{PWD}.'/m/config.pd',
	'makefile' => 'Makefile',
	'target_dir' => 'm/targets',
	'manifest' => $ENV{PWD}.'/MANIFEST',
	'fake_targets' => [qw/all realclean cpan/],
	'depends' => {
		'all' => [qw/compile test install/],
		'cpan' => [qw/compile dep test install/],
		'realclean' => [qw/clean/],
	},
	'help' => {
		'compile' => 'Prepare all files for installation',
		'install' => 'Install Zoidberg on your system',
		'all' => 'Compile, test, install',
		'help' => 'print this text',
		'new_dep' => 'generate Depends.pd and t/use_ok.t',
		'check_manifest' => 'Check for missing files',
		'check_dep' => 'Check dependencies',
		'dep' => 'Fetch missings dependencies from CPAN',
		'cpan' => 'Make all and check deps from CPAN',
		'cvs' => 'Try checkout source tree from anonymous cvs',
	},
	'vars' => {
		'PREFIX' => '/usr/local',
		'LIB_PREFIX' => '',
		'LIB' => '',
		'TEST_VERBOSE' => 0,
		'VERBOSE' => 0,
		'PERL' => '/usr/bin/perl',
		'CONFIG' => '/etc',
		'INSTALLDIRS' => 'site',
		'NO_HTML_DOC' => 0,
	},
	'include' => {
		'NAME'		=> 'Zoidberg',
		'VERSION'	=> get_version_from('lib/Zoidberg.pm'),
		'AUTHOR'	=> 'Jaap G Karssenberg <j.g.karssenberg@student.utwente.nl> and RL Zwart <r.l.zwart@caremail.nl>',
		'PREREQ_PM'	=> $depends,
	},
	'help_postamble' =>
"--[ Zoidberg ]

  Use \"make all\" to install Zoidberg

  The LIB_PREFIX var overloads the INSTALLDIRS var.
  (LIB and LIB_PREFIX are the same -- added LIB after reading CPAN docs)
  The place where libraries and man pages are installed is _not_
  influenced by PREFIX.

  try \"perl Makefile.PL LOCAL_DIR=my_dir\" for a private installation

  See also <http://Zoidberg.sourceforge.net>",

);

my $make = Makefile->new(\%config);

if ($make->{vars}{LOCAL_DIR}) { # overrule other settings
	$make->{vars}{PREFIX} = $make->{vars}{LOCAL_DIR};
	$make->{vars}{CONFIG} = $make->{vars}{LOCAL_DIR}.'/etc/';
	$make->{vars}{LIB_PREFIX} = $make->{vars}{LOCAL_DIR}.'/lib/';
	$make->{vars}{PERS_DIR} = $make->{vars}{LOCAL_DIR}.'/dump';
	$make->{vars}{INSTALLMAN1DIR} = $make->{vars}{LOCAL_DIR}."/man1/";
	$make->{vars}{INSTALLMAN3DIR} = $make->{vars}{LOCAL_DIR}."/man3/";
	$make->{vars}{share} = $make->{vars}{LOCAL_DIR}.'/share';
	for (qw/LOCAL_DIR PREFIX CONFIG LIB_PREFIX share INSTALLMAN1DIR INSTALLMAN3DIR/) {
		unless (-d $make->{vars}{$_}) { mkdir $make->{vars}{$_}; }
	}
}

$make->check_manifest;
$make->check_dep || print "==> Try \"make dep\" to fetch missing modules from CPAN.\n";
$make->write_makefile;


__END__


##  If you are looking for a listing of Dependencies please see b/Requires.pd  ##

use lib './b';

require MyBuilder;
require File::Spec;

my $requires = do File::Spec->catfile(qw/b Requires.pd/);
$$requires{perl} = '5.6.1'; # I don't trust older versions will work

my $build = MyBuilder->new(
	module_name => 'Zoidberg',
	dist_author => 'Jaap Karssenberg <pardus@cpan.org>',
	license => 'perl',
	requires => $requires,
	recommends => {
		'Term::ReadLine::Zoid' => 0,
		'Env::PS1' => 0,
		'Storable' => 0,
	},
	build_requires => {
		'Module::Build' => '0.24',
		'Data::Dumper' => '0',
		'Pod::Text' => 0,
		'Test::More' => 0,
	},
	create_makefile_pl => 'passthrough',
	dynamic_config => {}, # boolean but bug (!?) in M:B
	PL_files => {}, # make it ignore my stuff
#	autosplit => ['lib/Zoidberg/Fish/Commands.pm'],
);

$build->MyInit;
$build->create_build_script;

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'Zoidberg',
    'VERSION_FROM'	=> 'Zoidberg.pm', # finds $VERSION
    'PREREQ_PM'		=> {
    	## dependencies getopt::long abd pod::usage are for the scripts in ProgramFiles
	'Getopt::Long' => '',
	'Pod::Usage'	=> '',

	'Term::ANSIColor' => '1.05',
	'Data::Dumper' => '2.12',
	'Zoidberg::PdParse' => '0.04',
	'POSIX' => '1.05',
    },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Zoidberg.pm', # retrieve abstract from module
       AUTHOR     => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>') : ()),
);




use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Zoidberg::History',
    'VERSION_FROM'	=> 'History.pm', # finds $VERSION
        'PREREQ_PM' => {
                'Zoidberg::Fish' => '0.1',
        },

    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'History.pm', # retrieve abstract from module
       AUTHOR     => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>') : ()),
);

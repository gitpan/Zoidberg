use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Zoidberg::Test',
    'VERSION_FROM'	=> 'Test.pm', # finds $VERSION
        'PREREQ_PM' => {
                'Data::Dumper' => '2.12',
                'Zoidberg::Fish' => '0.1',
                'Zoidberg::StringParse' => '0.1',
        },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Test.pm', # retrieve abstract from module
       AUTHOR     => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>') : ()),
);

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'Zoidberg::Commands',
    'VERSION_FROM'	=> 'Commands.pm',
        'PREREQ_PM' => {
                'Devel::Symdump' => '2.03',
                'Data::Dumper' => '2.12',
                'Zoidberg::Fish' => '0.1',
        },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Commands.pm', # retrieve abstract from module
       AUTHOR     => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>') : ()),
);

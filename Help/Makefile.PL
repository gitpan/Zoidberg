use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Zoidberg::Help',
    'VERSION_FROM'	=> 'Help.pm', # finds $VERSION
        'PREREQ_PM' => {
                'Zoidberg::Fish' => '0.1',
                'Devel::Symdump' => '2.03',
                'Data::Dumper' => '2.12',
                'Pod::Text::Color' => '1.04',
                'IO::File' => '1.09',
        },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Help.pm', # retrieve abstract from module
       AUTHOR     => 'Raoul Zwart <carlos@caremail.nl>') : ()),
);

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Zoidberg::Hermes',
    'VERSION_FROM'	=> 'Hermes.pm', # finds $VERSION
        'PREREQ_PM' => {
                'Zoidberg::Fish' => '0.1',
                'DBI' => '1.30',
        },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Hermes.pm', # retrieve abstract from module
       AUTHOR     => 'Raoul Zwart <carlos@caremail.nl>') : ()),
);

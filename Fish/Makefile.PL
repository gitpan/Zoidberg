use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'Zoidberg::Fish',
    'VERSION_FROM'	=> 'Fish.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Fish.pm', # retrieve abstract from module
       AUTHOR     => 'Raoul Zwart <carlos@caremail.nl>') : ()),
);

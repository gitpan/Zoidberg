use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Zoidberg::Help',
    'VERSION_FROM'	=> 'Help.pm', # finds $VERSION
    'PREREQ_PM'		=> {
    	'Devel::Symdump' => '2.03'
    }, 
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Help.pm', # retrieve abstract from module
       AUTHOR     => 'Raoul Zwart <carlos@caremail.nl>') : ()),
);

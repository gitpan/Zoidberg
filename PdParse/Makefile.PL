use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
          'NAME' => 'Zoidberg::PdParse',
          'AUTHOR' => 'Raoul Zwart <carlos@caremail.nl>',
          'VERSION_FROM' => 'PdParse.pm',
          'ABSTRACT_FROM' => 'PdParse.pm',
          'PREREQ_PM' => {
                           'Storable' => '2.04'
                         }
                );

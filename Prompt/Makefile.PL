use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
          'NAME' => 'Zoidberg::Prompt',
          'AUTHOR' => 'Raoul Zwart <carlos@caremail.nl>',
          'VERSION_FROM' => 'Prompt.pm',
          'ABSTRACT_FROM' => 'Prompt.pm',
          'PREREQ_PM' => {
                           'Term::ANSIColor' => '1.05'
                         }
                );

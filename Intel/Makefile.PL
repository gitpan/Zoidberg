use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
          'NAME' => 'Zoidberg::Intel',
          'AUTHOR' => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>',
          'VERSION_FROM' => 'Intel.pm',
          'ABSTRACT_FROM' => 'Intel.pm',
          'PREREQ_PM' => {
                           'Devel::Symdump' => '2.03'
                         }
                );

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
          'NAME' => 'Zoidberg::Intel',
          'AUTHOR' => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>',
          'VERSION_FROM' => 'Intel.pm',
          'ABSTRACT_FROM' => 'Intel.pm',
        'PREREQ_PM' => {
                'Zoidberg::StringParse' => '0.1',
                'Zoidberg::Fish' => '0.1',
                'Data::Dumper' => '2.12',
                'Devel::Symdump' => '2.03',
                'Storable' => '2.04',
        },

);

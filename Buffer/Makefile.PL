use ExtUtils::MakeMaker;

WriteMakefile(
          'NAME' => 'Zoidberg::Buffer',
          'AUTHOR' => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>',
          'VERSION_FROM' => 'Buffer.pm',
          'ABSTRACT_FROM' => 'Buffer.pm',
          'PREREQ_PM' => {
                'Data::Dumper' => '2.12',
                'POSIX' => '1.05',
                'Term::ReadKey' => '2.21',
                'Term::ANSIScreen' => '1.40',
                'Zoidberg::StringParse' => '0.1',
                'Zoidberg::StringParse::Syntax' => '0.1',
                'Zoidberg::Fish' => '0.1'
                         }
                );

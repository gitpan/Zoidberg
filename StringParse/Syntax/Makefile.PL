use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
          'NAME' => 'Zoidberg::StringParse::Syntax',
          'AUTHOR' => 'J.G. Karssenberg <j.g.karssenberg@student.utwente.nl>',
          'VERSION_FROM' => 'Syntax.pm',
            #'ABSTRACT_FROM' => 'Syntax.pm',
        'PREREQ_PM' => {
                'Term::ANSIColor' => '1.05',
                'Zoidberg::StringParse' => '0.1',
        },
);

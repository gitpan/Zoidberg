use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
          'NAME' => 'Zoidberg::Trog',
          'AUTHOR' => 'Raoul Zwart <carlos@caremail.nl>',
          'VERSION_FROM' => 'Trog.pm',
        'PREREQ_PM' => {
                'POSIX' => '1.05',
                'IO::File' => '1.09',
                'Zoidberg::Fish' => '0.1',
        },

);

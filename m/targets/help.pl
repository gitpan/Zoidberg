
require 'm/Makefile.pm';

my $make = Makefile->new;

my $name = $make->{include}{NAME} || 'unknown';
my $version = $make->{include}{VERSION} || 'unknown';
my $author = $make->{include}{AUTHOR} || 'unknown';
print << "END"

## This package uses Makefile.pm -- yet another approach to Makefile.PL
## by Jaap Karssenberg || Pardus [Larus] --=-- 2003

--[ Package information ]

 NAME    : $name
 VERSION : $version
 AUTHOR  : $author

--[ Usage ]

 > make [target] [VAR1=value] [VAR2=value]

--[ Known make targets ]

END
;

for (@{$make->{target_names}}) { print '  '.$_.($make->{help}{$_} ? ' :  '.$make->{help}{$_} : '')."\n"; }
print "\n--[ Variables ]\n\n";
for (keys %{$make->{vars}}) { print '  '.$_.($make->{vars}{$_} ? ' :  '.$make->{vars}{$_} : '')."\n"; }

print "\n".$make->{help_postamble}."\n\n";


__END__

=head1 NAME

help

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

This target prints a dynamicly generated help text listing available targets and variables.
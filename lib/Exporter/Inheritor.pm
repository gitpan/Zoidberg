package Exporter::Inheritor;

use strict;
use Carp;
require Exporter;

our @ISA = qw/Exporter/;
our $VERSION = 0.1;
our $DEBUG = 0;

sub import {
        my $class = shift;
	return if $class eq __PACKAGE__;
        no strict 'refs';

        for my $sub ( grep /^\w/, (@_ || @{$class.'::EXPORT'}) ) { # only subs start with \w - right ?
                next if *{$class.'::'.$sub}{CODE};
                for (@{$class.'::ISA'}) {
			next if $_ eq __PACKAGE__;
                        next unless *{$_.'::'.$sub}{CODE};
                        carp "Found routine $sub for class $class in class $_\n" if $DEBUG;
                        *{$class.'::'.$sub} = *{$_.'::'.$sub}{CODE};
                        last;
                }
        }

	if ( $class->can('_bootstrap') ) {
		eval qq{
			package $class;
			_bootstrap(\@_)
		};
	}

	unshift @_, $class;
        goto &Exporter::import; # let exporter do it's thing
}

1;

__END__

=head1 NAME

Exporter::Inheritor - export subroutines from parent classes

=head1 SYNOPSIS

See L<Exporter>, this is a transparant sub class.

=head1 DESCRIPTION

This module is a B<quick and dirty hack> to enables a module to export
subroutines from parent classes.
It prepares the module on import while simply using Exporter for the dirty work.
Also it calls a sub C<_bootstrap()> if it exists before exporting. Arguments to C<_bootstrap()>
will be the same as to import.

=head1 BUGS

Somehow it only works in combination with strict.

The order packages (within the same file) are in matters a lot :S

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Exporter>

=cut


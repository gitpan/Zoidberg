package Devel::GetSymbols;
use strict;
use vars qw($VERSION @EXPORT_OK);
use base 'Exporter';
use Carp;

@EXPORT_OK = qw(symbols subs);

$VERSION = '0.01';

no strict 'refs';

sub symbols {
    my ($type, $package) = @_;
    $package = (caller)[0] unless defined $package;
    croak 'Usage: symbols(type[, package])' unless defined $type;
    grep defined *{"${package}::$_"}{$type}, keys %{"${package}::"}
}

sub subs () { symbols( CODE => (caller)[0] ) }

1;

__END__

=head1 NAME

Symbol::List - get a list of symbols that match a certain type

=head1 SYNOPSIS

    use Devel::GetSymbols qw(symbols subs);
    my @subroutines = symbols('CODE');
    my @subroutines = subs(); # equal
    # @subroutines includes 'symbols', because it was imported
    # into this package.

    use Data::Dumper;
    print "$_\n" for symbols('SCALAR', 'Data::Dumper');

    use base 'Exporter';
    @EXPORT_OK = symbols('CODE');                # Yuch.
    @EXPORT_OK = subs();                         # Ditto.
    @EXPORT = grep /^[A-Z_]+$/, symbols('CODE'); # Export constants

=head1 DESCRIPTION

This module just does a grep on some keys, but can save a lot of development
time.

=over 10

=item symbols

Takes type and optional package name as arguments and returns a list of symbols
that are of that type and in that package. Defaults to the calling package.
Type can be one of qw(ARRAY CODE FORMAT GLOB HASH IO SCALAR). I guess C<CODE>
will be used most :)

=item subs

Shorthand for C<symbols('CODE')>. Does not take arguments (use C<symbols>
if you want to get it from another package).

=back

=head1 KNOWN BUGS

None yet

=head1 AUTHOR

Juerd <juerd@juerd.nl>

Copyright (C) 2002 J. Waalboer

=cut

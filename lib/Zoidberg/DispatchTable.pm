package Zoidberg::DispatchTable;

our $VERSION = '0.3b';

use strict;
use Carp;
use Tie::Hash;
our @ISA = qw/Tie::ExtraHash/;

# perl 5.6 version of Tie::Hash doesn't include ExtraHash
eval join '', (<DATA>) unless *Tie::ExtraHash::TIEHASH{CODE};

sub wipe {
	my $self = shift;
	my $tag = shift || croak q{Cowardly refusing to wipe the whole dispatch table};
	my $count = 0;
	for (keys %{$self->[0]}) {
		delete(${$self->[0]}{$_}) && $count++
			if ref($self->[0]{$_}) eq 'ARRAY'
			&& $self->[0]{$_}[1] eq $tag;
	}
	return $count;
}

sub TIEHASH  { 
	my $class = shift;
	my $ref = shift;
	my $hash = shift || {};
	croak q{First argument should be an object reference} 
		unless ( ref($ref) && ref($ref) ne 'HASH');
	bless [$hash, $ref], $class;
}

sub STORE { 
	my ($self, $key, $value) = @_;
	
	my $t = ref($value);

	unless ($t) { $value = $self->_check($value) }
	elsif ($t eq 'ARRAY') { $value->[0] = $self->_check($value->[0]) }
	elsif ($t ne 'CODE') { croak qq{Can't use a $t reference as sub routine} }
	
	$self->[0]{$key} = $value;
}

sub _check {
	my $self = shift;
	my $value = shift;
	$value =~ s/(^\s*|\s*$)//g;
	croak 'empty value not allowed' unless $value;
	croak 'value has an unsupported format' if $value =~ /^\$/;
	return $value;
}

sub FETCH {
	my ($self, $key) = @_;
	return undef unless exists ${$self->[0]}{$key};
	
	my $value = $self->[0]{$key};
	my $t = ref $value;
	
	if ($t eq 'CODE') { return $value }
        elsif ($t eq 'ARRAY') {
		return $value->[0] if ref($value->[0]) eq 'CODE';
		$value->[0] = $self->_convert($value->[0]);
		$self->[0]{$key} = $value;
		return $value->[0];
	}
	else {  # no ref I hope
		$self->[0]{$key} = $self->_convert($value);
		return $self->[0]{$key};
	}
}

sub _convert {
	my $self = shift;
	my $ding = shift;
		
        $ding =~ s{^->((\w+)->)?}{
		$self->[1]->can('parent')
		? q#parent->#.( $1 ? qq#object('$2')-># : '' )
		: ( $1 ? qq#object('$2')-># : '' )
	}e;

        if ($ding =~ /\(.*\)$/) { $ding =~ s/\)$/, \@_\)/ }
	else { $ding .= '(@_)' }
	
	#print "# going to eval: -->sub { \$self->[1]->$ding }<--\n";
	return eval("sub { \$self->[1]->$ding }");
}

1;

__DATA__
package Tie::ExtraHash;

sub TIEHASH  { my $p = shift; bless [{}, @_], $p }
sub STORE    { $_[0][0]{$_[1]} = $_[2] }
sub FETCH    { $_[0][0]{$_[1]} }
sub FIRSTKEY { my $a = scalar keys %{$_[0][0]}; each %{$_[0][0]} }
sub NEXTKEY  { each %{$_[0][0]} }
sub EXISTS   { exists $_[0][0]->{$_[1]} }
sub DELETE   { delete $_[0][0]->{$_[1]} }
sub CLEAR    { %{$_[0][0]} = () }


__END__

=head1 NAME

Zoidberg::DispatchTable - class to tie dispatch tables

=head1 SYNOPSIS

	use Zoidberg::DispatchTable;
	
	my %table;
	tie %table, q{Zoidberg::DispatchTable}, 
		$self, 
		{ cd => '->Commands->cd' };
	
	# The same as $self->parent->object('Commands')->cd('..') if
	# a module can('parent'), else the same as $self->Commands->cd('..')
	$table{cd}->('..');
	
	$table{ls} = q{ls('-al')}
	
	# The same as $self->ls('-al', '/data')
	$table{ls}->('/data');

=head1 DESCRIPTION

This module can be used tie tie hashes functioning as dispatch tables.
It enforces zoidbergs string notation for subroutines.

=head1 EXPORT

None by default.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


package Zoidberg::DispatchTable;

our $VERSION = '0.3c';

use strict;
use Carp;

sub TIEHASH { goto &Zoidberg::DispatchTable::Hash::TIEHASH }
sub TIEARRAY { goto &Zoidberg::DispatchTable::Array::TIEARRAY }

sub wipe {
	my $self = shift;
	my $tag = shift || croak q{Cowardly refusing to wipe the whole dispatch table};
	my $count = 0;
	if (ref($self) =~ /Hash/) {
		for (keys %{$self->[0]}) {
			delete(${$self->[0]}{$_}) && $count++
				if ref($self->[0]{$_}) eq 'ARRAY'
				&& $self->[0]{$_}[1] eq $tag;
		}
	}
	else { # Array
		@{$self->[0]} = grep {defined $_} map {
			( (ref($_) eq 'ARRAY') && ($_->[1] eq $tag) && ++$count)
			? undef
			: $_
		} @{$self->[0]};
	}
	return $count;
}

sub tag {
	my ($self, $id) = @_;
	$id = $self->[3] unless defined $id;
	my $value = ( ref($self) =~ /Hash/ ) ? $self->[0]{$id} : $self->[0][$id];
	return ( ref($value) eq 'ARRAY' ) ? $value->[1] : undef ;
}

sub check { # returns undef if value is wrong
	my ($self, $value) = @_;
	my $t = ref($value);
	my $s;
	
	unless ($t) { $s = $value }
	elsif ($t eq 'ARRAY') { $s = $value->[0] }
	elsif ($t ne 'CODE') { return undef }

	if ($s) {
		$s =~ s/(^\s*|\s*$)//g;
		return undef if $s !~ /\S/; # no empty values
		return undef if $s =~ /^\$/; # no vars
	}

	return $value;
}

sub convert {
	my ($self, $ding) = @_;
		
        $ding =~ s{^->((\w+)->)?}{
		$self->[2]
		? q#parent->#.( $1 ? qq#object('$2')-># : '' )
		: ( $1 ? qq#object('$2')-># : '' )
	}e;

        if ($ding =~ /\(.*\)$/) { $ding =~ s/\)$/, \@_\)/ }
	else { $ding .= '(@_)' }
	
	#print "# going to eval: -->sub { \$self->[1]->$ding }<--\n";
	my $sub = eval("sub { \$self->[1]->$ding }");
	die if $@;
	return $sub;
}

package Zoidberg::DispatchTable::Array;

use strict;
use Carp;
#use Tie::Array;
our @ISA = qw/Zoidberg::DispatchTable/; # Tie::Array/;

sub TIEARRAY {
	shift;
	my $ref = shift;
	my $arr = shift || [];
	croak q{First argument should be an object reference}
		unless ( ref($ref) && ref($ref) ne 'ARRAY' );
	bless [$arr, $ref, $ref->can('parent')];
}

sub STORE {
	my ($self, $i, $value) = @_;
	$value = $self->check($value) || croak "Can't use -->$value<-- as subroutine.";
	$self->[0][$i] = $value;
}

sub FETCH {
	my ($self, $i) = @_;
	$self->[3] = $i;
	return undef unless exists $self->[0][$i];
	
	my $value = $self->[0][$i];
	my $t = ref $value;
	return $value if $t eq 'CODE';

        if ($t eq 'ARRAY') {
		return $value->[0] if ref($value->[0]) eq 'CODE';
		$self->[0][$i][0] = $self->convert( $value->[0] );
		return  $self->[0][$i][0];
	}
	else {  # no ref I hope
		$self->[0][$i] = $self->convert($value);
		return $self->[0][$i];
	}
}

sub EXISTS { exists $_[0]->[0][$_[1]] }

sub DELETE { delete $_[0]->[0][$_[1]] }

sub CLEAR { $_[0]->[0] = [] }

sub EXTEND {}

sub FETCHSIZE { return scalar @{$_[0]->[0]} }

sub PUSH { 
	my $self = shift;
	my @values = map { $self->check($_) || croak "Can't use -->$_<-- as subroutine." } @_;
	push @{$self->[0]}, @values;
}

sub POP {
	my $self = shift;
	return undef unless scalar($self->[0]);
	my $sub = $self->FETCH(-1);
	pop @{$self->[0]};
	return $sub;
}

sub SHIFT {
	my $self = shift;
	return undef unless scalar($self->[0]);
	my $sub = $self->FETCH(0);
	shift @{$self->[0]};
	return $sub;
}

sub UNSHIFT {
	my $self = shift;
	my @values = map { $self->check($_) || croak "Can't use -->$_<-- as subroutine." } @_;
	unshift @{$self->[0]}, @values;
}

package Zoidberg::DispatchTable::Hash;

use strict;
use Carp;
use Tie::Hash;
our @ISA = qw/Zoidberg::DispatchTable Tie::ExtraHash/;

# perl 5.6 version of Tie::Hash doesn't include ExtraHash
eval join '', (<DATA>) unless *Tie::ExtraHash::TIEHASH{CODE};

sub TIEHASH  { 
	shift;
	my $ref = shift;
	my $hash = shift || {};
	croak q{First argument should be an object reference}
		unless ( ref($ref) && ref($ref) ne 'HASH');
	bless [$hash, $ref, $ref->can('parent')];
}

sub STORE { 
	my ($self, $key, $value) = @_;
	$value = $self->check($value) || croak "Can't use -->$value<-- as subroutine.";
	$self->[0]{$key} = $value;
}

sub FETCH {
	my ($self, $key) = @_;
	$self->[3] = $key;
	return undef unless exists ${$self->[0]}{$key};

	my $value = $self->[0]{$key};
	my $t = ref $value;
	return $value if $t eq 'CODE';

        if ($t eq 'ARRAY') {
		return $value->[0] if ref($value->[0]) eq 'CODE';
		$self->[0]{$key}[0] = $self->convert( $value->[0] );
		return  $self->[0]{$key}[0];
	}
	else {  # no ref I hope
		$self->[0]{$key} = $self->convert($value);
		return $self->[0]{$key};
	}
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


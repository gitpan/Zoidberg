package Zoidberg::DispatchTable;

our $VERSION = '0.41';

use strict;
use Carp;
use Zoidberg::Utils qw/debug/;
use Exporter::Tidy all => [qw/stack wipe/];

# $self->[0] hash with arrays of dispatch strings/refs
# $self->[1] hash with arrays of tags
# $self->[2] object ref
# $self->[3] object can parent bit
# $self->[4] array with keys to keep them in order

sub TIEHASH  {
	my $class = shift;
	my $ref = shift || croak 'need object ref to tie hash';
	# $ref is either array ref or object ref
	my $self = (ref($ref) eq 'ARRAY')
		? $ref
		: [{}, {}, $ref, $ref->can('parent'), []];
	bless $self, $class;
	for my $ref (@_) { $self->STORE($_, $$ref{$_}) for keys %$ref }
	return $self;
}

sub STORE { 
	my ($self, $key, $value) = @_;
	my $tag = 'undef';
	($value, $tag) = @$value if ref($value) eq 'ARRAY';
	
	if (ref($value) eq 'HASH') {
		unless (tied $value) {
			my %value;
			tie %value, __PACKAGE__, $$self[2], $value;
			$value = \%value;
		}
	}
	elsif (ref($value) ne 'CODE') {
		$value =~ s/(^\s*|\s*$)//g;
		croak "Can't use ==>$value<== as subroutine."
			if ! length($value)
			or $value =~ /^\$/; # no vars
	}
	push @{$self->[0]{$key}}, $value;
	push @{$self->[1]{$key}}, $tag;
	push @{$self->[4]}, $key;
}

sub FETCH {
	my ($self, $key) = @_;
	if ($self->EXISTS($key)) {
		$self->[0]{$key}[-1] = $self->convert($self->[0]{$key}[-1])
			unless ref($self->[0]{$key}[-1]) eq 'CODE'
			or     ref($self->[0]{$key}[-1]) eq 'HASH';
		return $self->[0]{$key}[-1];
	}
	elsif ($self->EXISTS('_AUTOLOAD')) {
		my $sub;
		for (@{$self->[0]{_AUTOLOAD}}) {
	        	$sub = $_->($key);
        		next unless $sub;
		        $self->STORE($key, $sub);
        		return $self->FETCH($key);
		}
	}
	return undef;
}

sub convert {
	my ($self, $ding) = @_;

        $ding =~ s#^->((\w+)->)?#
		( $self->[3] ? q/parent->/         : '' ) .
		( $1         ? qq/{objects}{$2}->/ : '' )
	#e;

	if ($ding =~ /\(\s*\)$/) { $ding =~ s/\s*\)$/\@_\)/ }
        elsif ($ding =~ /\(.*\)$/) { $ding =~ s/\)$/, \@_\)/ }
	else { $ding .= '(@_)' }

	debug "going to eval: ==>sub { \$self->[2]->$ding }<==\n";
	my $sub = eval("sub { \$self->[2]->$ding }");
	die if $@;
	return $sub;
}

sub EXISTS { exists $_[0][0]->{$_[1]} and scalar @{$_[0][0]->{$_[1]}} }

sub DELETE { # doesn't really delete, merely pops
	my ($self, $key) = @_;
	return undef unless exists $self->[0]{$key};

	pop @{$self->[1]{$key}};
	my $re = pop @{$self->[0]{$key}};
	
	unless (scalar @{$self->[0]{$key}}) {
		delete $self->[0]{$key};
		delete $self->[1]{$key};
		@{$self->[4]} = grep {$_ ne $key} @{$self->[4]};
	}
	
	return $re;
}

sub CLEAR    { 
	%{$_[0][0]} = ();
	%{$_[0][1]} = ();
	@{$_[0][4]} = ();
}

our $Iter = 0;

sub FIRSTKEY {
	$Iter = 0;
	goto \&NEXTKEY
}

sub NEXTKEY  {
	my $self = shift;
	if ($Iter > scalar @{$self->[4]}) {
		$Iter = 0;
		return wantarray ? () : undef;
	}
	elsif (wantarray) {
		my $key = $self->[4][$Iter++];
		return $key, $self->FETCH($key);
	}
	else { return $self->[4][$Iter++] }
}

sub stack {
	my ($table, $key, $use_tag) = @_;
	my $self = tied %$table;
	for (@{$self->[0]{$key}}) {
		$_ = $self->convert($_)
			unless ref($_) eq 'CODE'
			or     ref($_) eq 'HASH';
	}
	return map [ $$self[0]{$key}[$_], $$self[1]{$key}[$_] ], (0..$#{$$self[0]{$key}})
		if $use_tag;
	return @{$self->[0]{$key}};
}

sub wipe {
	my ($table, $tag, @keys) = @_;
	my $self = tied %$table;
	@keys = keys %{$self->[0]} unless scalar @keys;
	my %old;
	for my $key (@keys) {
		for (my $i = 0; $i < @{$self->[1]{$key}}; $i++) {
			next unless $self->[1]{$key}[$i] eq $tag;
			$old{$key} = [$self->[0]{$key}[$i], $tag];
			$self->[0]{$key}[$i] = undef;
			$self->[1]{$key}[$i] = undef;
		}
		@{$self->[0]{$key}} = grep {defined $_} @{$self->[0]{$key}};
		@{$self->[1]{$key}} = grep {defined $_} @{$self->[1]{$key}};
		unless (scalar @{$self->[0]{$key}}) {
			delete $self->[0]{$key};
			delete $self->[1]{$key};
			@{$self->[4]} = grep {$_ ne $key} @{$self->[4]};
		}
	}
	return \%old;
}

package Zoidberg::DispatchScalar;

use Carp;
our @ISA = qw/Zoidberg::DispatchTable/;

sub TIESCALAR {
	my $class = shift;
        my $ref = shift || croak 'need object ref to tie hash';
        # $ref is either array ref or object ref
        my $self = (ref($ref) eq 'ARRAY')
                ? $ref
                : [undef, undef, $ref, $ref->can('parent')];
        bless $self, $class;
        $self->STORE($_) for @_;
        return $self;
}

sub STORE {
	my ($self, $value) = @_;
	if (ref($value) ne 'CODE') {
		$value =~ s/(^\s*|\s*$)//g;
		croak "Can't use ==>$value<== as subroutine."
			if ! length($value)
			or $value =~ /^\$/; # no vars
	}
	$$self[0] = $value;
}

sub FETCH {
	my $self = shift;
	return sub {} unless $$self[0];

	$$self[0] = $self->convert($$self[0])
		unless ref($$self[0]) eq 'CODE';
	return $$self[0];
}

1;

__END__

=head1 NAME

Zoidberg::DispatchTable - class to tie dispatch tables

=head1 SYNOPSIS

	use Zoidberg::DispatchTable;

	my %table;
	tie %table, q{Zoidberg::DispatchTable},
		$self, { cd => '->Commands->cd' };

	# The same as $self->parent->{objects}{Commands}->cd('..') if
	# a module can('parent'), else the same as $self->Commands->cd('..')
	$table{cd}->('..');

	$table{ls} = q{ls('-al')}

	# The same as $self->ls('-al', '/data')
	$table{ls}->('/data');

=head1 DESCRIPTION

This module provides a tie interface for converting config strings
to CODE references. It takes an object references (C<$self>) 
as starting point for resolving subroutines.
If the object has a method C<parent()> the refrence returned by this 
method is used as the root for resolving subroutines, else the object
itself is used as root.
The root is expected to contain a hash C<{objects}> (possibly of the 
class L<Zoidberg::PluginHash>) with references to "child" objects.

Strings are converted to CODE references at first use to save time
at initialisation.

The following strings are supported:

  String              Interpretation
  ----------          -----------------
  sub                 Sub of the reference object
  ->sub               Sub of the root object
  ->sub(qw/f00 b4r/)  Sub of the root object with arguments
  ->object->sub       Sub of a child object of the root
  ->sub()->..         Sub of the root object

You can store either config strings or CODE references in the table.

If you store an ARRAY ref it is expected to be of the form C<[$value, $tag]>,
where C<$tag> is an identifier used for handling selections of the table.
If you store a HASH ref it will be tied recursively as a DispatchTable.

Also keys are kept in the order they are first added, and for each key a stack
is used. Deleting a key only pops it's stack.

I< This modules doesn't check for security issues, it just runs arbitrary code. >

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


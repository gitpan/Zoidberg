
# Hic sunt leones.

package Zoidberg::StringParser::grammar;

# Adapted Tie-Hash-Stack-0.09 by Michael K. Neylon 
# to do more specific stuff for us, like avoiding 
# problems with lexical aliasing and do some grammar 
# specific stuff on the fly. Subclassing was not a
# option :(

use strict;
use Carp;
use Exporter::Tidy default => [qw/pop_stack push_stack empty_stack/];

sub TIEHASH {
	my $class = shift;
	my $newhash = pop || {};
	return tied %$newhash  # this is the lexical scoping hack
		if ref($newhash) eq 'HASH'
		&& ref( tied %$newhash ) eq __PACKAGE__ ;
	my @stack = map { (ref($_) eq 'ARRAY') ? @$_ : $_ } ($newhash, reverse @_) ;
	@stack = map { _prepare_gram($_) } @stack;
	my $self = bless [\@stack, 0], $class;
	$self->_index_gram;
	return $self;
}

sub _index_gram {
	my $self = shift;
	for (qw/d_esc tokens nests quotes/) { 
		push @{$self->[0][0]{_elements}}, $_
			if $self->EXISTS($_) && length $self->FETCH($_)
	}
}

sub FETCH {
    my ($self, $key) = @_;
    foreach ( @{$self->[0]} ) { return $_->{ $key } if exists $_->{ $key } }
    return undef;
}

sub STORE { $_[0]->[0][0]{ $_[1] } = $_[2] }

sub DELETE {
    my ($self, $key) = @_;
    my $return = $self->FETCH( $key );
    foreach ( @{$self->[0]} ) { delete $_->{ $key } if exists $_->{ $key } }
    return $return;
}

sub EXISTS {
    my ($self, $key) = @_;
    foreach ( @{$self->[0]} ) { return 1 if exists $_->{ $key } }
    return undef;
}

sub FIRSTKEY {
    my $self = shift;
    my %hash;
    foreach ( @{$self->[0]} ) {
	foreach my $key ( keys %$_ ) {
	    $hash{ $key } = 1;
	}
    }
    my @keys = sort keys %hash;
    return $keys[ 0 ];
}

sub NEXTKEY {
    my $self = shift;
    my $lastkey = shift;
    my %hash;
    foreach ( @{$self->[0]} ) {
	foreach my $key ( keys %$_ ) { 
	    $hash{ $key } = 1;
	}
    }
    my @keys = sort keys %hash;
    my $i = 0;
    $i++ while ( ( $lastkey ne $keys[ $i ] ) && ( $i < @keys - 1 ) ) ;
    if ( $i == @keys - 1 ) { return () } 
    else { return $keys[ $i+1 ] }
}

sub push_stack {
    my $href = shift;
    my $obj = tied %$href;
    my $addhash = shift || {};
    croak "First argument must be a tied hash in push_stack"
      unless $obj and $obj->isa(__PACKAGE__);
    _prepare_gram($addhash);
    unshift @{$obj->[0]}, $addhash;
    $obj->[1]++;
    $obj->_index_gram;
}

sub pop_stack {
    my $href = shift;
    my $obj = tied %$href;
    croak "First argument must be a tied hash in pop_stack"
      unless $obj and $obj->isa(__PACKAGE__);
    shift @{$obj->[0]} if $obj->[1];
    $obj->[1]--;
}

sub empty_stack {
	my $href = shift;
	my $obj = tied %$href;
	croak "First argument must be a tied hash in empty_stack"
	      unless $obj and $obj->isa(__PACKAGE__);
	return $obj->[1] ? 0 : 1;
}

sub _prepare_gram {
	my $ref = shift;

	my $t = ref $ref;
	if ($t eq 'HASH') { return $ref if $ref->{_prepared} }
	elsif ($t eq 'Regexp') { $ref = {tokens => [[$ref, '_CUT']], was_regexp => 1} }
	# TODO more data types ?
	else { croak "Grammar has wrong data type: $t\n" }

	$ref->{_elements} = [];

	if (exists($ref->{esc}) && ! exists($ref->{s_esc})) {
		unless (ref $ref->{esc}) {
			$ref->{s_esc} = quotemeta $ref->{esc};		# single esc regexp
			$ref->{d_esc} = '('.($ref->{s_esc}x2).')|';	# double esc regexp
		}
		else {
			$ref->{s_esc} = $ref->{esc};
			$ref->{d_esc} = '';
		}
	}
	elsif (exists $ref->{s_esc}) { $ref->{d_esc} = '' }

	for (qw/tokens nests quotes/) {
		next unless exists $ref->{$_};
		my $t = ref $ref->{$_};
		croak q/Brances of grammars can't be scalar/ unless $t;
		if (grep {$t eq $_} qw/HASH ARRAY/) {
			my $c =  'Zoidberg::StringParser::'. lc($t);
			$ref->{$_} = $c->new($ref->{$_});
		}
		# else do nothing -- assume it to be a well behaved object
	}

	if ($ref->{meta}) {
		croak q/'meta' should be a CODE reference/ 
			unless ref($ref->{meta}) eq 'CODE'; 
	}

	$ref->{_prepared}++;
	return $ref;
}

package Zoidberg::StringParser::array;

use strict;

sub new {
	my ($class, $array) = @_;
	my $expr = join( '|', map {
		ref($_->[0])
		? $_->[0]
		: quotemeta($_->[0])
	} @{$array} );
	$expr = $expr ? '('.$expr.')|' : '';
	bless [$expr, $array], $class;
}

sub fetch {
	my ($self, $key) = @_;
	my ($ref) = grep { 
		ref($_->[0])
		? ( $key =~ $_->[0] )
		: ( $key eq $_->[0] )
	} @{$self->[1]};
	return $key if $ref->[1] eq '_SELF';
	return $ref->[1];
}

package Zoidberg::StringParser::hash;

use strict;

sub new {
	my ($class, $hash) = @_;
	my $expr = join( '|', map { quotemeta($_) } keys %{$hash} );
	$expr = $expr ? '('.$expr.')|' : '';
	bless [$expr, $hash], $class;
}

sub fetch { $_[0]->[1]{$_[1]} }

package Zoidberg::StringParser;

our $VERSION = '0.54';

use strict;
no warnings; # can't stand the nagging
use Carp;
use Zoidberg::Utils qw/debug/;

import Zoidberg::StringParser::grammar;

sub new {
	my $class = shift;
	my $self = {
		base_gram  => shift || {},
		collection => shift || {},
		settings   => shift || {},
	};
	bless $self, $class;
	$self->reset;
	return $self;
}

sub set {
	my $self = shift;
	$self->reset;
	my $gram = shift || {};

	unless (ref $gram) {
		$gram = $self->{collection}{$gram} 
			|| croak "No such grammar: $gram" 
	}
	elsif (ref($gram) eq 'ARRAY') {
		$gram = [ map {
			ref($_) ? $_ : ($self->{collection}{$_} || croak "No such grammar: $_")
		} @$gram ];
	}
	my %gram;
	tie %gram, 'Zoidberg::StringParser::grammar', $self->{base_gram}, $gram;
	$self->{grammar} = \%gram;

	$self->{string} = shift unless ref $_[0]; # speed hack
	@{$self->{next_line}} = @_;
}

sub reset { 
	my $self = shift;
	$self->{grammar} = {};
	$self->{string} = '';
	$self->{broken} = undef;
	$self->{error} = undef;
	$self->{next_line} = [];
}

sub more { return length($_[0]->{string}) || $_[0]->next_line }

sub get { # get next block
	my ($self, $no_pull) = @_;
	
	return undef unless length $self->{string} or ! $no_pull && $self->more;

	my ($block, $_gref);
	if (ref $self->{broken}) { ($block, $_gref) = @{$self->{broken}} }
	else { $_gref = $self->{grammar} }
#	my %gram = %{$_gref};
	tie my %gram, 'Zoidberg::StringParser::grammar', $_gref;

	my ($token, $type, $sign);
	while (  !$token &&
		$self->{string} =~ s{
			\A(.*?)
			(
				$gram{d_esc}
				$gram{tokens}[0]
				$gram{nests}[0]
				$gram{quotes}[0]
				\z
			)
		}{}xs
	) {
		$block .= $1 if length $1;
		$sign = $2;

		debug "block: ==>$block<== token: ==>$sign<==";

		if ($1 =~ /$gram{s_esc}$/) { # escaped token
			$block =~ s/$gram{s_esc}$// unless $gram{no_esc_rm};
			$block .= $sign;
			next;
		}

		last unless length($sign) || length($self->{string}); # catch the \z

		my $i = 0;
		($_ eq $2) ? last : $i++ for ($3, $4, $5);
		$type = $gram{_elements}[$i];
		debug "type: $type";

		if ($type eq 'd_esc') { $block .= $gram{no_esc_rm} ? $sign  : $gram{esc} }
		elsif ($type eq 'tokens') {
			if (empty_stack(\%gram)) { $token = $gram{tokens}->fetch($sign) }
			else { # shouldn't we use _POP here ?
				$block .= $sign;
				pop_stack(\%gram);
			}
		}
		else { # open nest or quote
			$block .= $sign;
			my $item = $gram{$type}->fetch($sign);
			if (ref $item) { push_stack(\%gram, \%$item) } # stack grammar
			elsif ($item eq '_REC') { push_stack(\%gram, {}) } # recurs
			else { # generate a grammar on the fly
				my %m_gram = ($type eq 'nests')
					? (
						tokens => {$item => '_POP'},
						nests => {$sign => '_REC'},
					)
					: (
						tokens => {$item => '_POP'},
						quotes => {$sign => '_REC'},
						nests => {},
					);
				push_stack(\%gram, \%m_gram);
			}
			$gram{_open} = [$sign, $type]; # backup for error message
		}
		last unless length $self->{string};
	}

	unless (empty_stack(\%gram)) { # broken
		die q{This should never happen - died to prevent infinite loop} if $self->{string};
		# FIXME - it will happen when you escape the \z ... i think
		debug "stack not empty";
		$self->{broken} = [$block, \%gram];
		unless ($self->{settings}{allow_broken}) {
			if ($self->more) { ($block, $token) = $self->get } # recurs
			else {
				debug "broken input";
				$gram{_open}[1] =~ s/s$// ;
				$self->error( qq#Unmatched $gram{_open}[1] at end of input: $gram{_open}[0]# );
			}
		}
	}

	$block = $gram{meta}->($self, $block) if $gram{meta}; # post parse block
	# FIXME after recurs the post parse can happen two times 

	$token = undef if $token eq '_CUT';
	return( $token ?  ($block, $token) : $block );
}

sub split {
	my $self = shift;
	$self->set(@_);
	my @blocks = $self->_bulk_get(0, (
		$self->{grammar}{was_regexp}
		&& ! $self->{settings}{no_split_intel}
	) );
	return @blocks;
}

sub getline {
	my $self = shift;
	$self->set(@_);
	$self->_bulk_get(1, 0);
}

sub _bulk_get {
	my ($self, $one_line, $no_ref) = @_;

	return undef unless length $self->{string} or $self->next_line;

	my (@blocks, $block, $sign);
	while  (length $self->{string}) {
		($block, $sign) = $self->get(1);
		unless ( $no_ref or ! defined $block or ref $block ) {
			my $tmp = $block; # vunzig zo te moeten copieren
			$block = \$tmp;
		}
		push @blocks, $block, $sign;
		last unless length($self->{string})
			|| $one_line
			|| $self->next_line;
	}

	return grep {defined $_} @blocks;
}

sub next_line {
	my $self = shift;
	debug 'fetching next line of input';
	
	my $source = shift || $self->{next_line};
	my $broken = shift || (ref $self->{broken}) ? 1 : 0;

	return 0 unless scalar @{$source};
	
	my ($type, $line, $succes) = (undef, '', 0);
	unless ($type = ref $source->[0]) {
		$line = shift @{$source};
		$succes++
	}
	elsif ($type eq 'ARRAY') {
		$succes = $self->next_line($source->[0]); # recurs
		shift @{$source} unless scalar @{$source->[0]};
	}
	elsif ($type eq 'CODE') {
		$line = $source->[0]->($broken);
		if (defined $line) { $succes++ }
		else { shift @{$source} }
	}
	elsif ( UNIVERSAL::can($type, 'getline') ) {
		$line =  $source->[0]->getline;
		if (defined $line) { $succes++ }
		else { shift @{$source} }
	}
	else {
		$self->error(q{Can't fetch next line from reference type }.$type);
		shift @{$source};
	}
	
	$self->{string} .= $line;
	return $succes;
}

sub error { 
	my $self = shift;
	if (@_) { 
		$self->{error} .= ($self->{error} ? "\n" : '') . join("\n", @_);
		die $self->{error} . "\n" if $self->{settings}{raise_error};
	}
	return $self->{error} || undef;
}

1;

__END__

=head1 NAME

Zoidberg::StringParser - simple string parser

=head1 SYNOPSIS

	my $base_gram = {
	    esc => '\\',
	    quotes => {
	        q{"} => q{"},
	        q{'} => q{'},
	    },
	};

	my $parser = Zoidberg::StringParser->new($base_gram);

	my @blocks = $parser->split(
	    qr/\|/, 
	    qq{ls -al | cat > "somefile with a pipe | in it"} );

	# @blocks now is: 
	# ('ls -al ', ' cat > "somefile with a pipe | in it"');
	# So it worked like split, but it respected quotes

=head1 DESCRIPTION

This module is a simple syntaxt parser. It originaly was designed 
to work like the built-in C<split> function, but to respect quotes.
The current version is a little more advanced: it uses user defined 
grammars to deal with delimiters, an escape char, quotes and braces.
Also these grammars can contain hooks to add meta information to each
splitted block of text. The parser has a 'pull' mechanism to allow
line-by-line parsing, or to define callbacks for when for example
an unmatched bracket is encountered.

Yes, I know of the existence of L<Text::Balanced>, but I wanted to do this the hard way :)

I<All grammars and collections of grammars should be considered PRIVATE when used by a Z::SP object.>

=head1 EXPORT

None by default.

=head1 GRAMMARS

TODO

=over 4

=item esc

FIXME

If this is an Regexp ref, no double-escape removal is done. Probably if you use a Regexp ref
as ecape you also want to set L</no_esc_rm>.

=item no_esc_rm

Boolean that tells the parser not to remove the escape char when an escaped token
is encountered. Double escapes won't be replaced either. Usefull when a string needs 
to go through a chain of parsers.

=back

=head2 Collection

The collection hash is simply a hash of grammars with the grammar names as keys.
When a collection is given all methods can use a grammar name instead of a grammar.

=head2 Base grammar

This can be seen as the default grammar, to use it leave the grammar undefined when calling 
a method. If this base grammar is defined I<and> you specify a grammar at a method call, 
the specified grammar will overload the base grammar.

=head1 METHODS

=over 4

=item C<new(\%base_grammar, \%collection, \%settings)>

Simple constructor. See L</Collection>, 
L</Base grammar> and  L</settings> for explanation of the arguments.

=item C<set($grammar, @input_methods)>

Sets begin state for parser. C<$grammar> can either be a hash ref containing a grammar or
be the name (key) of a grammar in C<%collection>. See L<input methods> for possible values
of C<@input_methods>.

=item C<reset()>

Remove all state information from the parser. Also removes any error messages.

=item C<more()>

Test for more input. Can trigger the pull mechanism.

Intended usage:

	$p->set($grammar, @input);
	while ($p->more) {
		($block, $token) = $p->get()
	}

=item C<get()>

Get next block from input. Intended for atomic use, for most situations either
C<split> or C<getline> will do. 

=item C<next_line()>

Loads next line of input from L</input methods>. This method is called internally by the pull mechanism.
Intended for atomic use.

=item C<split($grammar, @input_methods)>

Get all blocks till input returns C<undef>. Arguments are passed directly to C<set()>.
Blocks will by default be passed as scalar refs (unless the grammar's meta function altered them) and tokens as scalars.
To be a little compatible with C<CORE::split> all items (blocks and tokens) are passed
as plain scalars if C<$grammar> is or was a Regexp reference. ( This behaviour can be faked by giving 
your grammr a value called 'was_regexp'. ) This behaviour is turned off by the L</no_split_intel> setting.

=item C<getline($grammar, @input_methods)>

Like split but gets only one line from input and without the "intelligent" behaviour. 
B<Will> try to get more input when the syntax is incomplete unless L</allow_broken> is set.

=item C<error()>

Returns parser error if any. Returns undef if all is well.

=back

=head2 input methods

FIXME

=head2 settings

The C<%settings> hash contains options that control the  general behaviour of the parser.
Supported settings are:

=over 4

=item allow_broken

If this value is set the parser will not automaticly pull from input when broken syntax is 
encountered. Very usefull in combination with the C<getline()> method to make sure just 
one line is read and parsed even if this leaves us with broken syntax.

=item raise_error

Boolean that controls whether the parser dies when an error is encountered - see L</DIAGNOSTICS>. 

=item no_split_intel

Boolean, disables "intelligent" behaviour of C<split()> when set.

=back

=head1 DIAGNOSTICS

By default this module will croak for fatal errors like wrong argument types only. For less-fatal
errors it sets the error function. Notice that some of these "less-fatal" errors
may turn out to be fatal after all. If the C<raise_error> setting is set all errors
will raise an exception.

FIXME splain error messages

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

Contains some code derived from Tie-Hash-Stack-0.09 by Michael K. Neylon.

=head1 SEE ALSO

L<Zoidberg>

=cut


package Zoidberg::Parser;

our $VERSION = '0.41';

use strict;
use Zoidberg::Contractor;
use Zoidberg::StringParser;
use Zoidberg::Utils qw/:error :output read_data_file is_exec_in_path abs_path/;

our @ISA = qw/Zoidberg::Contractor/;

sub new {
	my $self = bless {}, shift;
	init($self);
}

sub init {
	my $self = shift;

	$self->{_pending} = [];

	my $coll = read_data_file('grammar');
	$self->{stringparser} = Zoidberg::StringParser->new($coll->{_base_gram}, $coll);

	## context stuff
	# {contexts}{$context} exists of word_list block_filter intel and handler
	my %contexts;
	tie %contexts, 'Zoidberg::DispatchTable', $self;
	$self->{contexts} = \%contexts;

	Zoidberg::Contractor::init($self);
}

sub round_up { Zoidberg::Contractor::round_up(@_) }

sub shell_string {
	my $self = shift;
	local $ENV{ZOIDREF} = $self;
	my @list = eval { $self->parse(@_) };
	return complain if $@;
	return $self->shell_list(@list); # calling contractor
}

sub parse {
	my $self = shift;
	my @tree = $$self{stringparser}->split('script_gram', @_);
	if (my $e = $self->{stringparser}->error) { error $e }
	# TODO pull code here
	debug 'raw parse tree: ', \@tree;
        @tree = grep {defined $_} map { ref($_) ? $self->parse_block($$_) : $_} @tree;
	debug 'parse tree: ', \@tree;
        return @tree;
}

sub parse_block  { # mag schoner, doch werkt
	# args: string, broken_bit (also known as "Intel bit")
	my ($self, $string, $bit) = @_;
	my $ref = [ { broken => $bit }, $string ];

	# check block contexts
	debug 'trying custom block contexts';
	for (keys %{$self->{contexts}}) {
		next unless exists $self->{contexts}{$_}{block_filter};
		@$ref = $self->{contexts}{$_}{block_filter}->(@$ref);
		last if length $$ref[0]{context};
	}

	unless (length $$ref[0]{context} or $self->{settings}{_no_hardcoded_context}) {
		debug 'trying default block contexts';
		@$ref = $self->_block_context(@$ref)
	}

	# check word contexts
	unless (length $$ref[0]{context}) {
		my @words = ($#$ref > 1) 
			? @$ref[1 .. $#$ref]
			: $self->_split_words($$ref[1], $$ref[0]{broken});
		$ref = [$$ref[0], @words];

		unless (grep {length $_} @words) { return undef }
		elsif ($$ref[0]{broken} && $#words < 1) { # default for intel
			$$ref[0]{context} = '_WORDS';
			return $ref;
		}

		@$ref = $self->parse_words(@$ref);
	}

	$$ref[0]{string} = $string; # attach _original_ string
	return $ref;
}

sub _block_context {
	my ($self, $meta, $block) = @_;
	my $perl_regexp = join '|', @{$self->{settings}{perl_keywords}};
	if (
		$block =~ s/^\s*(\w*){(.*)}(\w*)\s*$/$2/s
		or $$meta{broken} && $block =~ s/^\s*(\w*){(.*)$/$2/s
	) {
		$$meta{context} = uc($1) || 'PERL';
		$$meta{opts} = $3;
		if (lc($1) eq 'zoid') {
			$$meta{context} = 'PERL';
			$$meta{dezoidify} = 1;
		}
		elsif (
			$$meta{context} eq 'SH' or $$meta{context} eq 'CMD'
			or exists $self->{contexts}{$$meta{context}}{word_list}
		) {
			$block = [ $self->_split_words($block, $$meta{broken}) ];
			$$meta{context} = '_WORDS' if $$meta{broken} and $#$block < 1;
		}
	}
	elsif ( $block =~ /^\s*(->|[\$\@\%\&\*\xA3]\S|\w+\(|($perl_regexp)\b)/s ) {
		$$meta{context} = 'PERL';
		$$meta{dezoidify} = 1;
	}
	
	return($meta, $block);
}

sub parse_words {
	my ($self, $meta, @words) = @_;

	# parse redirections
	unless (
		$self->{settings}{_no_redirection}
		|| ($#words < 2)
		|| $words[-2] !~ /^(\d?)(>>|>|<)$/
	) {
		# FIXME what about escapes ? (see posix spec)
		my $num = $1 || ( ($2 eq '<') ? 0 : 1 );
		$$meta{fd}{$num} = [pop(@words), $2];
		pop @words;
	}

	# check builtin cmd and sh context
	unless ( $self->{settings}{_no_hardcoded_context} ) {
		debug 'trying default word contexts';
#		no strict 'refs';
		if (
#			defined *{"Zoidberg::Eval::$words[0]"}{CODE} or
			exists $self->{commands}{$words[0]}
		) { $$meta{context} = 'CMD' }
		elsif (
			($words[0] =~ m!/! and -x $words[0] and ! -d $words[0])
			or is_exec_in_path($words[0])
		) { $$meta{context} = 'SH' }
		$$meta{_is_checked}++ if $$meta{context};
	}

	# check dynamic word contexts
	unless (length $$meta{context}) {
		debug 'trying custom word contexts';
		for (keys %{$self->{contexts}}) {
			next unless exists $self->{contexts}{$_}{word_list};
			my $r = $self->{contexts}{$_}{word_list}->($meta, @words);
			next unless $r;
			$meta = $r if ref $r;
			$$meta{context} ||= $_;
			last;
		}
	}

	# hardcoded default context
	unless (
		length $$meta{context}
		or $self->{settings}{_no_hardcoded_context}
	) { $$meta{context} = 'SH' }

	return($meta, @words);
}

sub _split_words {
	my ($self, $string, $broken) = @_;
	my @words = grep {length $_} $self->{stringparser}->split('word_gram', $string);
	# grep length instead of defined to remove empty parts resulting from whitespaces
	# FIXME this causes intel to strip spaces from begin of string
	unless ($broken) { @words = $self->__do_aliases(@words) }
	else { push @words, '' if (! @words) || ($string =~ /(\s+)$/ and $words[-1] !~ /$1$/) }
	return @words; # filter out empty fields
}

sub __do_aliases { # FIXME should use perser subroutine
	my ($self, $key, @rest) = @_;
	if (exists $self->{aliases}{$key}) {
		my $alias = $self->{aliases}{$key};
		# TODO Should we support other data types ?
		@rest = $self->__do_aliases(@rest)
			if $alias =~ /\s$/; # recurs - see posix spec
		unshift @rest, 
			($alias =~ /\s/)
			? ( grep {$_} $self->{stringparser}->split('word_gram', $alias) )
			: ( $alias );
		return @rest;
	}
	else { return ($key, @rest) }
}

1;

__END__

=head1 NAME

Zoidberg::Parser - Parses statements to jobs

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

This module is not intended for external use ... yet.
Zoidberg inherits from this module, it handles the parsing of command input.
It inherits from Zoidberg::Contractor itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Contractor>

=head1 AUTHORS

Jaap Karssenberg, E<lt>pardus@cpan.orgE<gt>

Raoul Zwart, E<lt>rlzwart@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Jaap Karssenberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

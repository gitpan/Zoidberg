package Zoidberg::StringParse::Syntax;

our $VERSION = '0.1';

use strict;
use Term::ANSIColor;
use base 'Zoidberg::StringParse';

sub parse {
	#args: $string or [@strings], optional: gram_name
	my $self = shift;
	my $string_or_ref = shift;
	my $gram = shift || $self->{default};
	my ($no_error_bit, $no_modify) = @_;
	unless (ref($string_or_ref) eq 'ARRAY') { $string_or_ref = [$string_or_ref]; }

	$self->flush; # for non flushing use parse_string
	unless ($gram eq $self->{last}) {
		$self->{last} = $gram;
		$self->prepare_gram;
	}
	#print "Debug: using gram: $gram"; print $self->{collection}{$self->{last}} ? "--this exists\n" : "\n";
	foreach my $string (@{$string_or_ref}) { $self->parse_string($string); }

	if ($self->{collection}{$self->{last}}{pre_rules_code}) { eval($self->{collection}{$self->{last}}{pre_rules_code}); };

	$self->parse_rules($self->{collection}{$self->{last}}{default_color}, $no_error_bit, $no_modify);

	if ($self->{collection}{$self->{last}}{post_rules_code}) { eval($self->{collection}{$self->{last}}{post_rules_code}); };

	return $self->stringify;
}

sub stringify {
	my $self = shift;
	my $string = '';
	foreach my $block (@{$self->{tree}}) {
		#print 'debug: '.join('--', @{$block})."\n";
		if ( ($block->[2]) && (grep {$block->[2] =~ /^$_$/i} @{$self->{ansi_colors}}) ) {
			#print "debug: is ansi\n";
			$string .= color(lc($block->[2])).$block->[0].color('reset');
			unless (($block->[1] eq 'END') || ($block->[1] eq 'BROKEN')) {
				$string .= $block->[1];
			}
		}
		else {
			$string .= $block->[0];
			unless (($block->[1] eq 'END') || ($block->[1] eq 'BROKEN')) {
				$string .= $block->[1];
			}
		}
	}
	return $string;
}

sub gen_rules {
	my $self = shift;
	if ($self->{collection}{$self->{last}}{colors}) {
		foreach my $color (keys %{$self->{collection}{$self->{last}}{colors}}) {
			my $exp = '('.join('|', @{$self->{collection}{$self->{last}}{colors}{$color}}).')';
			unshift @{$self->{collection}{$self->{last}}{rules}}, ['^'.$exp.'$', $color];
		}
	}
}

sub prepare_gram {
	my $self = shift;
	if (@_) { $self->{ansi_colors} = shift; }
	unless ($self->{collection}{$self->{last}}{expr}) { $self->gen_expr; }
	unless ($self->{collection}{$self->{last}}{made_rules}) {
		$self->gen_rules;
		$self->{collection}{$self->{last}}{made_rules} = 1;
	}
}

1;
__END__

=head1 NAME

Zoidberg::StringParse::Syntax use StringParse for Syntax Highlighting

=head1 SYNOPSIS

  use Zoidberg::StringParse::Syntax;
  my $parser = Zoidberg::StringParse::Syntax->new;
  my $string = 'some string';
  my $colored_string = $parser->parse($string);

=head1 ABSTRACT

  This module does syntax highlighting for Zoidberg

=head1 DESCRIPTION

This subclass of Zoidberg::StringParse manipulates its parent
class to be usefull for syntax highlighting.
It uses Term::ANSIColor for the actual highlighting.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 new()

  Simple constructor, you can suppply a custom grammar as arg.

=head2 parse($string)

  Returns highlighted version of $string.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::StringParse>

http://zoidberg.sourceforge.net.

=cut


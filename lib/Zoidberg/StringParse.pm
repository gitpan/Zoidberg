package Zoidberg::StringParse;

##Insert version Zoidberg here##

use strict;
use Data::Dumper;

sub new {
	# args: ref_to_grammar_tree, name_default
	my $class = shift;
	my $self = {};
	my $ding = shift;
	unless (ref($ding)) { $ding = eval($ding); }
	$self->{collection} = $ding;		# ref to hash tree with grammars
	$self->{default} = shift;		# name of default grammar
	$self->{last} = $self->{default};	# name of last used grammar
	$self->{stack} = [ ['root'] ];
	$self->{tree} = [];
	$self->{error} = '';
	bless $self, $class;
	$self->prepare_gram(@_);
	return $self;
}

sub flush {
	my $self = shift;
	my $error = $self->{error};
	if ($self->{tree}[0] && ($self->{tree}[-1][1] eq 'BROKEN') && !$error) { $error = 'BROKEN';}
	$self->{stack} = [['root']];
	$self->{tree} = [];
	$self->{error} = '';
	return $error;
}

sub parse {
	#args: $string or [@strings], optional: gram_name, no_error_bit mo_modify_bit
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

	#print  "debug: gram name: $gram\n";
	#print "debug: gram".Dumper($self->{collection}{$gram});
	foreach my $string (@{$string_or_ref}) { $self->parse_string($string); }

	if ($self->{collection}{$self->{last}}{pre_rules_code}) { eval($self->{collection}{$self->{last}}{pre_rules_code}); };

	if ($self->{tree}[-1][1] eq 'BROKEN') { $self->{error} = "Open block at end of syntax using grammar \'$self->{last}\'."; }
	if (!$no_error_bit && $self->{error}) { return []; }

	unless (@{$self->{tree}}) { @{$self->{tree}} = (['', '']); }
	$self->parse_rules($self->{collection}{$self->{last}}{default_context}, $no_error_bit, $no_modify);

	if ($self->{collection}{$self->{last}}{post_rules_code}) { eval($self->{collection}{$self->{last}}{post_rules_code}); };

	return $self->{tree};
}

sub parse_string {
	my $self = shift;
	my $string = shift;
	my $block = "";
	if ($self->{tree}[0] && $self->{tree}[-1][1] eq 'BROKEN') {
		$block = $self->{tree}[-1][0];
		pop @{$self->{tree}};
	}
	$string =~ s/(?:\A|\G)(.*?)(?<!$self->{collection}{$self->{last}}{escape})($self->{collection}{$self->{last}}{expr})/
		$block .= $1;
		if (my $sign = $2) {
			if ($self->{stack}[-1][0] eq "root") { #state root
				if (my ($ref) = grep {$sign =~ m\/^$_->[0]$\/} @{$self->{collection}{$self->{last}}{nests}}) { # open nest
					unless ($ref->[2] eq 'JOIN') {
						push @{$self->{tree}}, [$block, $sign, $self->{stack}[-1][3]];
						$block = "";
					}
					else { $block .= $sign; }
					push @{$self->{stack}}, ['nest', @{$ref}];
				}
				else {
					push @{$self->{tree}}, [$block, $2];
					$block = "";
				}
			}
			elsif ($2 =~ m\/^$self->{stack}[-1][2]$\/) { # close nest -- ivm quotes komt deze voor open
				if (($self->{stack}[-2][0] eq "root") && ($self->{stack}[-1][3] ne 'JOIN')){ # not nested nest && not join
					push @{$self->{tree}}, [$block, $sign, $self->{stack}[-1][3]];
					$block = "";
				}
				else { $block .= $sign; }
				pop @{$self->{stack}};
			}
			elsif ($2 =~ m\/^$self->{stack}[-1][1]$\/) { # open nested nest
				push @{$self->{stack}}, $self->{stack}[-1];
				$block .= $sign;
			}
			else { $block .= $2; } # nest die nu niet relevant is
		}
		"";
	/mge; #/
	$block .= $string; # pak laatste restje
	if ($self->{stack}[-1][0] eq "root") { push @{$self->{tree}}, [$block, 'END']; }
	else { push @{$self->{tree}}, [$block, 'BROKEN', $self->{stack}[1][3]]; }
	return $self->{tree};
}

sub prepare_gram {
	my $self = shift;
	unless ( $self->{collection}{$self->{last}}{expr} ) { $self->gen_expr; }
}

sub gen_expr {
	my $self = shift;
	my @limits = grep {$_} @{$self->{collection}{$self->{last}}{limits}};
	my @open = ();
	my @close = ();
	foreach my $ref (@{$self->{collection}{$self->{last}}{nests}}) {
		if ($ref->[0]) { push @open, $ref->[0]; }
		if ($ref->[1]) { push @close, $ref->[1]; }
	}
	for (\@limits, \@open, \@close) {
		my $string = join('|', @{$_});
		if ($string) {
			$self->{collection}{$self->{last}}{expr} .= $self->{collection}{$self->{last}}{expr} ? '|' : '' ;
			$self->{collection}{$self->{last}}{expr} .= $string;
		}
	}
}

sub parse_rules { #print "debug: parsing rules ...\n";
	my $self = shift;
	my ($default, $use_broken_rules, $no_modify) = @_;
	foreach my $block (@{$self->{tree}}) { #print "debug: gonna parse --$block--\n";
		if ($self->{collection}{$self->{last}}{use_aliases} && !$no_modify) {
			foreach my $alias (@{$self->{collection}{aliases}}) {
				$block->[0] =~ s/^\s*$alias->[0]/$alias->[1]/;
			}
		}
		unless ( ($block->[1] eq 'BROKEN') && $use_broken_rules) { #print "debug: gonna use normal rules\n";
			foreach my $rule (@{$self->{collection}{$self->{last}}{rules}}) {
				if ($block->[0] =~ /$rule->[0]/) { #print "debug success\n";
					$block->[2] = $rule->[1];
					if ($rule->[2] && !$no_modify) { eval ($rule->[2]); }
					if ($rule->[1]) { last; }
				}
			}
		}
		else {  #print "debug: broken rules apply\n";
			foreach my $rule (@{$self->{collection}{$self->{last}}{broken_rules}}) {
				if ($block->[0] =~ /$rule->[0]/) {
					$block->[2] = $rule->[1];
					if ($rule->[2] && !$no_modify) { eval ($rule->[2]); }
					if ($rule->[1]) { last; }
				}
			}
		}
		unless ($block->[2]) { $block->[2] = $default; }

		if ($block->[1] eq 'END') { $block->[1] = ''; }
		elsif ($block->[1] eq 'BROKEN') { $block->[1] = ''; }
	}
}

#+ memento mori
#
#sub {
#    my $self = shift;
#    our ($Sein, $Zeit) = @_;
#    unless ($self) {
#        *Zeit = \$Sein;
#        while (1) {}
#    }
#}

 
1;

__DATA__
my $default = {}


__END__

=head1 NAME

Zoidberg::StringParse - Zoidberg module for parsing strings to anything

=head1 SYNOPSIS

  use Zoidberg::StringParse;
  my $parser = Zoidberg::StringParse->new;
  my @parse_tree = $parser->parse($string);

=head1 ABSTRACT

  This module does dynamic string parsing for Zoidberg

=head1 DESCRIPTION

This module does dynamic string parsing for Zoidberg.
It uses 'grammars' to define the way a string is parsed.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 new()

  Simple constructor, you can suppply a custom grammar as arg.

=head2 parse($string)

  Returns the parse tree of $string as array ref.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

http://zoidberg.sourceforge.net.

=cut


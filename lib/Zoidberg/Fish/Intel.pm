package Zoidberg::Fish::Intel;

our $VERSION = '0.3a_pre1';

use strict;
use base 'Zoidberg::Fish';
use Devel::GetSymbols qw/symbols/;
use Zoidberg::Error;
use Zoidberg::FileRoutines qw/abs_path list_path get_dir/;

our $DEBUG = 0;

sub expand {
	my ($self, $string, $i_feel_lucky) = @_;

	my ($l_block, $block);

	($string, $l_block) = $self->_get_last_block($string);
	if ($l_block =~ /^\w*$/) { $block = [{ context => '_WORDS' }, $l_block] }
	else { 
		$block = $self->{parent}->_resolv_context($l_block, 'BROKEN'); 
		push @{$block}, '' if __is_word_cont($block) && $l_block =~ /\s$/;
	}

	$block->[0]{i_feel_lucky} = $i_feel_lucky;
	$block->[0]{poss} = [];
# print "string: -->$string<-- l_block -->$l_block<--\n";

# use Data::Dumper;
# print 'initial block', Dumper $block;

	$block = $self->_do($block, $block->[0]{context});

# print 'done block', Dumper $block;
	
	# recombine

	# if $block->[0] is an array ref , $block is really a list of blocks
	my $poss;
	if (ref($block->[0]) eq 'ARRAY') { 
		($block, $poss) = $self->_unwrap_nested_poss(@{$block});
	}
	else { $poss = $block->[0]{poss} }

# print scalar(@{$poss}), " poss\n";

	if (scalar @{$poss}) {
		my ($match, $winner);
		if (scalar(@{$poss}) == 1) {  # we have a winner
			$winner++;
			$match = shift @{$poss} 
		}
		else {
			# cross match all poss
			$match = $poss->[0];
# print "poss 0: -->$match<--\n";
			for my $p (@{$poss}) {
# print "poss: -->$p<--, match: -->$match<--\n";
				while ($p !~ /^\Q$match\E/) {
					$match = substr($match, 0, length($match)-1);
				}
				last unless $match;
			}
		}
# print "match: -->$match<--\n";
		# wrap it
		if ($match) {
			my $m_l_block = $self->_wrap($block, $match, $winner);
# print "m_l_block: -->$m_l_block<--\n";
			return ($block->[0]{message}, $string.$m_l_block, $poss)
				if length($m_l_block) > length($l_block);
		}
	}

	return ($block->[0]{message}, $string.$l_block, $poss);
}

sub _get_last_block {
	my ($self, $string) = @_;
	my @dinge = $self->{parent}{StringParser}->split('script_gram', $string);
	# remember @dinge contains scalar refs

	unless (scalar(@dinge) && ref $dinge[-1]) { return ($string, '') }

	my $block = ${$dinge[-1]};
	$string =~ s/\Q$block\E$//;
	return ($string, $block);
}

sub _unwrap_nested_poss {
	my ($self, @blocks) = @_;
	@blocks = grep {scalar @{$_->[0]{poss}}} @blocks;
	
	my $poss = [];
	unless (scalar @blocks) 	{ unshift @blocks, [{}] }
	elsif (scalar(@blocks) == 1)	{ $poss = $blocks[0]->[0]{poss} }
	else { $poss = [ map { @{$_->[0]{poss}} } @blocks ] }

	return ($blocks[0], $poss);
}

sub _do {
	my ($self, $block, $try, @try) = @_;
	print "_do is gonna try $try (".'i_'.lc($try).")\n" if $DEBUG;
	return $block unless $try;
	my @re;
	if (ref $try) { @re = $try->($self, $block, @try) }
	elsif (exists $self->{parent}{contexts}{lc($try).'_intel'}) {
		@re = $self->{parent}{contexts}{lc($try).'_intel'}->($self, $block, @try)
	}
	elsif ($self->can('i_'.lc($try))) {
		my $sub = 'i_'.lc($try);
		@re = $self->$sub($block, @try);
	}
	else { error $try.': no such expansion available' }

#print "scalar \@re is".scalar(@re)."\n";

	unless (scalar @re) { return scalar(@try) ? $self->_do($block, @try) : $block } # recurs
	elsif (scalar(@re) == 1) { return $re[0] }
	else { $self->_do(@re, @try) } # recurs 
}

sub _wrap {
	my ($self, $block, $string, $winner) = @_;
	return '' unless __is_word_cont($block);
	# TODO config 'n stuff !!!!!!!!!!!!111 !!!!!!!!!!!!11
	$string = $block->[0]{pref}.$string if $block->[0]{pref};
	$block->[-1] = $string if @{$block};
	my $re = join(' ', @{$block}[1 .. $#{$block}]);
	$re .= ' ' if $winner && $string !~ m#/$#;
	return $re;
}

sub __is_word_cont { grep {$_ eq lc($_[0]->[0]{context})} qw/_words cmd sh/ } # FIXME not transparent !

sub i__words { # TODO file & dirs in './'
	my ($self, $block) = @_;

	my @poss = $self->{parent}->list_commands;
	push @poss, list_path();

	for ($self->{parent}{_words_contexts}) {
		push @poss, $self->{parent}{contexts}{$_.'_list'}->()
			if exists $self->{parent}{contexts}{$_.'_list'};
	}

#	print "got into i__words - ".scalar(@poss)." opts \n";

	@poss = grep /^\Q$block->[-1]\E/, @poss;
	
#	print "got into i__words - ".scalar(@poss)." opts na grep \n";
	
	$block->[0]{poss} = \@poss;
	
	return $block;
}

sub i_sh {
	my ($self, $block) = @_;
	return ($block, ($block->[-1] =~ /^-/) ? '_man_opts' : '_files_n_dirs');
}

sub i_cmd { return ($_[1], '_files_n_dirs') }

sub i__files_n_dirs { # TODO globbing tab :)
	my ($self, $block) = @_;

	my $arg = $block->[-1];
	my $dir = ($arg =~ s!^(.*/)!!) ? abs_path($1) : '.';
	$block->[0]{pref} = $1;
	print "Expanding files from dir: $dir with arg: -->$arg<--\n" if $DEBUG;
	$dir = get_dir($dir);
	$block->[0]{poss} = [
		
		grep /^\Q$arg\E/, 
		map( {$_.'/'} @{$dir->{dirs}} ),
		@{$dir->{files}}, 
	];
	print "Got ".scalar(@{$block->[0]{poss}})." matches\n" if $DEBUG;
	return $block;
}

1;

__END__

=head1 NAME

Zoidberg::Fish::Intel - Zoidberg module handling tab expansion and globbing

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This class provides intelligence for tab-expansion
and similar functions. It is very dynamic structured.

=head2 EXPORT

None by default.

=head1 METHODS

FIXME

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>,
L<Zoidberg>,
L<Zoidberg::Fish>,
L<http://zoidberg.sourceforge.net>

=cut


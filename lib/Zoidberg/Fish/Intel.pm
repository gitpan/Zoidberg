package Zoidberg::Fish::Intel;

our $VERSION = '0.3c';

use strict;
use vars qw/$DEVNULL/;
use base 'Zoidberg::Fish';
use Devel::GetSymbols qw/symbols/;
use Zoidberg::Error;
use Zoidberg::FileRoutines qw/abs_path list_path get_dir $DEVNULL/;

our $DEBUG = 0;

sub init {
	my $self = shift;
	if ($self->{config}{man_cmd}) {} # TODO split \s+
}

sub expand {
	my ($self, $string, $i_feel_lucky) = @_;
	print "\n" if $DEBUG;

	# fetch block
	my $l_block;
	($string, $l_block) = $self->_get_last_block($string);
	print "string is -->$string<--\nl_block is -->$l_block<--\n" if $DEBUG;

	# find context of block
	my $block = $self->{parent}->parse_block($l_block, 'BROKEN');
	unless ($block) { return ('', $string.$l_block, []) }
	if ($#$block > 1) {
		# get pref right
		$block->[0]{pref} = $l_block;
		unless ( !length($block->[-1]) || $block->[0]{pref} =~ s/\Q$block->[-1]\E$//) {
			# probably escape chars make the match fail
			my @words = $self->{parent}{StringParser}->split(
				['word_gram', {no_esc_rm => 1}],
				$l_block );
			return ('', $string.$l_block, []) unless $block->[0]{pref} =~ s/\Q$words[-1]\E$//;
		}
	} else { $block->[0]{pref} = '' }
	$block->[0]{i_feel_lucky} = $i_feel_lucky;
	$block->[0]{poss} = [];

	$block = $self->do($block, $block->[0]{context});

	# recombine --  if $block->[0] is an array ref , $block is really a list of blocks
	my $poss;
	if (ref($block->[0]) eq 'ARRAY') {
		($block, $poss) = $self->_unwrap_nested_poss(@{$block});
	}
	else { $poss = $block->[0]{poss} }

	if (scalar @{$poss}) {
		my ($match, $winner);
		if (scalar(@{$poss}) == 1) {  # we have a winner
			$winner++;
			$match = shift @{$poss} 
		}
		else {
			# cross match all poss
			$match = $poss->[0];
			for my $p (@{$poss}) {
				while ($p !~ /^\Q$match\E/) {
					$match = substr($match, 0, length($match)-1);
				}
				last unless $match;
			}
		}
		# wrap it
		if ($match) {
			my $m_l_block = $self->_wrap($block, $match, $winner);
			return ($block->[0]{message}, $string.$m_l_block, $poss);
				# if length($m_l_block) > length($l_block); # Conflicts with escape chars
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

sub _wrap {
	my ($self, $block, $string, $winner) = @_;
	$string = _quote_file($string) if $block->[0]{_file_quote} ;
	$string = $block->[0]{pref} . $string;
	$string .= $block->[0]{postf} || ' ' if $winner && $string =~ m#\w$#; # FIXME not transparent !!
	return $string;
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

sub join {
	my ($self, @blocks) = @_;
	@blocks = map { (ref($_->[0]) eq 'ARRAY') ? @{$_} : $_ } @blocks;
	@blocks = ( [{}] ) unless scalar @blocks;
	return $#blocks ? [@blocks] : $blocks[0];
}

sub remove_doubles {
	my %dus;
	for (@_) { $dus{$_}++ }
	return sort keys %dus;
}

sub do {
	my ($self, $block, $try, @try) = @_;
	print "do is gonna try $try (".'i_'.lc($try).")\n" if $DEBUG;
	return $block unless $try;
	my @re;
	if (ref($try) eq 'CODE') { @re = $try->($self, $block) }
	elsif (exists $self->{parent}{contexts}{lc($try).'_intel'}) {
		@re = $self->{parent}{contexts}{lc($try).'_intel'}->($self, $block)
	}
	elsif ($self->can('i_'.lc($try))) {
		my $sub = 'i_'.lc($try);
		@re = $self->$sub($block);
	}
	else { print $try.': no such expansion available' if $DEBUG }

	if (defined $re[0]) { ($block, @try) = (@re, @try) }
	else { return scalar(@try) ? $self->do($block, @try) : $block } # recurs

	my $succes = 0;
	if (ref($block->[0]) eq 'ARRAY') { $succes++ if grep {$_->[0]{poss}} @{$block} }
	else { $succes++ if $block->[0]{poss} && scalar( @{$block->[0]{poss}} ) }

	if ($succes) { return $block }
	else { return scalar(@try) ? $self->do($block, @try) : $block } # recurs
}

sub i_perl { return ($_[1], qw/_zoid _perl_data/) }

sub i__zoid {
	my ($self, $block) = @_;

	return undef unless $block->[0]{dezoidify};
	return undef unless
		$block->[-1] =~ s/( (?:->|\xA3) (?:\S+->)* (?:[\[\{].*?[\]\}])* )(\S*)$//x;
	my ($pref, $arg) = ($1, qr/^\Q$2\E/);
	$block->[0]{pref} = $block->[-1] . $pref;
	
	my $code = "\$self->{parent}".$pref;
	$code =~ s/\xA3/->/;
	$code =~ s/->$//;
	my $ding = eval($code);
	my $type = ref $ding;
#	print "\ndebug: pref -->$pref<-- arg -->$arg<-- code -->$code<-- ref -->$type<--\n";
	return undef if $@ || ! $type;

	my @poss;
	if ($type eq 'HASH') { push @poss, sort grep m/$arg/, map {'{'.$_.'}'} keys %{$ding} }
	elsif ($type eq 'ARRAY') { push @poss, grep m/$arg/, map {'['.$_.']'} (0 .. $#$ding) }
	elsif ($type eq 'CODE' ) { $block->[0]{message} = "\'$pref\' is a CODE reference"   } # do nothing (?)
	else { # $ding is object
		if ( ($type eq ref $self->{parent}) && (!$ding->{settings}{naked_zoid} || $pref =~ /\xA3/) ) {
			# only dispay clothes
			push @poss, grep m/$arg/, @{$self->parent->list_vars};
			push @poss, grep m/$arg/, @{$self->parent->list_clothes};
			push @poss, grep m/$arg/, @{$self->parent->list_objects};
			$block->[0]{postf} = '->';
		}
		else {
			if (UNIVERSAL::isa($ding, 'HASH')) { push @poss, sort grep m/$arg/, map {'{'.$_.'}'} keys %{$ding} }
			elsif (UNIVERSAL::isa($ding, 'ARRAY')) { push @poss, grep m/$arg/, map {'['.$_.']'} (0 .. $#$ding) }

			unless ($arg =~ /[\[\{]/) {
				no strict 'refs';
				my @m_poss = map { grep  m/$arg/, symbols('CODE', $_) } ($type, @{$type.'::ISA'});
				push @poss, remove_doubles(@m_poss);
			}
			$block->[0]{postf} = '(';
		}
	}
	if ($self->{parent}{settings}{hide_private_method} && $arg !~ /_/) {
		@poss = grep {$_ !~ /^\{?_/} @poss;
	}
	$block->[0]{poss} = \@poss;

	return $block;
}

sub i__perl_data { return undef } # TODO

sub i__words {
	my ($self, $block) = @_;

	my $arg = $block->[-1];
	$block->[0]{poss} = [ grep /^\Q$arg\E/, $self->{parent}->list_commands ];
	push @{$block->[0]{poss}}, grep( /^\Q$arg\E/, list_path() ) unless $arg =~ m#/#;

	return ($block, qw/exec __more_words/);
}

sub i___more_words {
	my ($self, $block) = @_;
	for (@{$self->{parent}{_word_lists}}) {
		push @{$block->[0]{poss}}, $_->($block->[-1]) 
	}
	return $block;
}

sub i_sh {
	my ($self, $block) = @_;
	return ($block, ($block->[-1] =~ /^-/) ? 'man_opts' : 'dirs_n_files');
}

sub i_cmd { return ($_[1], 'dirs_n_files') }

sub i_dirs { i_dirs_n_files(@_, 'd') }
sub i_files { i_dirs_n_files(@_, 'f') }
sub i_exec { i_dirs_n_files(@_, 'x') }

sub i_dirs_n_files { # TODO globbing tab :)
	my ($self, $block, $type) = @_;
	$type = 'df' unless $type;

	my $arg = $block->[-1];
	$arg =~ s#\\##g;

	my $dir;
	if ($arg =~ m#^~# && $arg !~ m#/#) { # expand home dirs
		$dir = { 
			dirs => [ map {"~$_"} list_users() ],
			files => [],
			path => '~',
		}
	}
	else {
		$dir = ($arg =~ s!^(.*/)!!) ? abs_path($1) : '.';
		$block->[0]{pref} .= _quote_file($1);
		return undef unless -d $dir;
		$dir = get_dir($dir);
	}
	print "Expanding files ($type) from dir: $dir->{path} with arg: -->$arg<--\n" if $DEBUG;
	
	my @poss = sort grep /^\Q$arg\E/, @{$dir->{files}};
	@poss = grep { -x $dir->{path}.$_ } @poss if $type =~ /x/;

	unshift @poss, sort grep /^\Q$arg\E/, map( {$_.'/'} @{$dir->{dirs}}, qw/. ../ ) if $type =~ /d|x/;

	@poss = grep {$_ !~ /^\./} @poss
		if $self->{parent}{settings}{hide_hidden_files} && $arg !~ /^\./;

	$block->[0]{_file_quote}++;
	$block->[0]{poss} = \@poss;

	print "Got ".scalar(@{$block->[0]{poss}})." matches\n" if $DEBUG;
	return $block;
}

sub _quote_file { 
	my $string = shift;
	$string =~ s#([\[\]\(\)\s\?\!\#\;\:\"\'\{\}])#\\$1#g;
	return $string;
}

sub i_users {
	my ($self, $block) = @_;
	$block->[0]{poss} = [ grep /^\Q$block->[-1]\E/, list_users() ];
	return $block;
}

sub list_users {
	my ($u, @users);
	setpwent;
	while ($u = getpwent) { push @users, $u }
	return @users;
}

sub i_man_opts { # TODO caching (tie classe die ook usefull is voor FileRoutines ?)
	my ($self, $block) = @_;
	return unless $self->{config}{man_cmd} && $block->[1];
	
	# re-route STDERR
	open SAVERR, '>&STDERR';
	open STDERR, '>'.$DEVNULL;
	
	print "Going to open pipeline '-|', '$self->{config}{man_cmd}', '$block->[1]'\n" if $DEBUG;
	open MAN, '-|', $self->{config}{man_cmd}, $block->[1];
	my (%poss, @poss, $state, $desc);
	# state 3 = new alinea
	#       2 = still parsing options
	#       1 = recoding description
	#       0 = skipping
	while (<MAN>) { # line based parsing ...
		if ($state > 1) { # FIXME try to expand "zoid --help" & "zoid --usage"
			# search for more options
			s/\e.*?m//g; # de-ansi-fy
			s/.\x08//g;  # remove backspaces
			unless (/^\s*-{1,2}\w/) { $state = ($state == 3) ? 0 : 1 }
			else { $state = 2 }
			$desc .= $_ if $state;
			next unless $state > 1;
			while (/(-{1,2}[\w-]+)/g) { push @poss, $1 unless exists $poss{$1} }
		}
		elsif ($state == 1) {
			if (/\w/) { $desc .= $_ }
			else {
				$state = 3;
				# backup description
				my $copy = $desc || '';
				for (@poss) { $poss{$_} = \$copy }
				($desc, @poss) = ('', ());
			}
		}
		else { $state = 3 unless /\w/ }
	}
	close MAN;

	open STDERR, '>&SAVERR';
	
#	use Data::Dumper;
#	print Dumper \%poss;
	
	$block->[0]{poss} = [ grep /^\Q$block->[-1]\E/, sort keys %poss ];
	$block->[0]{message} = ${$poss{$block->[0]{poss}[0]}} if scalar(@{$block->[0]{poss}}) == 1;
	$block->[0]{message} =~ s/[\s\n]+$//;

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

=head2 Build-in expansions

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

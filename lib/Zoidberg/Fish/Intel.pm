package Zoidberg::Fish::Intel;

our $VERSION = '0.53';

use strict;
use vars qw/$DEVNULL/;
use Zoidberg::Fish;
use Zoidberg::Utils qw/:error debug abs_path list_path list_dir/;
use Zoidberg::DispatchTable _prefix => '_', 'stack';

our @ISA = qw/Zoidberg::Fish/;

sub init {
	my $self = shift;
	if ($self->{config}{man_cmd}) {} # TODO split \s+
}

sub completion_function {
	my ($self, $word, $buffer, $start) = @_;
	debug "\ncomplete for predefined word '$word' starting at $start";
	my ($m, @c) = $self->complete($word, $buffer, $start);
	my $diff = $start - $$m{start}; # their word isn't ours
	return if $diff < 0; # you never know
	$diff -= length substr $$m{prefix}, 0, $diff, '';
	if ($diff) { # we can't be sure about the real length due to escapes
		if (substr($c[0], 0, $diff) =~ /^(.*\W)/) { $diff = length $1 }
		substr $_, 0, $diff, '' for @c;
	}
	elsif (length $$m{prefix}) { @c = map {$$m{prefix}.$_} @c }
	if (@c == 1) { # postfix only if we have a match
		$c[0] .= $$m{postfix};
		$c[0] .= $$m{quoted}.' ' if $c[0] =~ /\w$/;
	}
	return @c;
}

sub complete {
	my ($self, $word, $buffer, $start) = @_;
	my $cursor = $start + length $word;

	# fetch block
	$buffer = substr $buffer, 0, $cursor;
	my ($pref, $block) = $self->_get_last_block($buffer);
#	$$block[0]{i_feel_lucky} = $i_feel_lucky; TODO, also T:RL:Zoid support for this
	$$block[0]{quoted} = $1 if $$block[-1] =~ s/^(['"])//;

	debug "\ncompletion start block: ", $block;
	$block = $self->do($block, $$block[0]{context});
	$block = $self->join_blocks(@$block) if ref($$block[0]) eq 'ARRAY';
	my %meta = (
		start => length $pref,
		( map {($_ => $$block[0]{$_})} qw/message prefix postfix quoted/ )
	);
	$meta{prefix} = $meta{quoted} . $meta{prefix} if $meta{quoted};
	debug scalar(@{$$block[0]{poss}}) . ' completions, meta: ', \%meta;
	return (\%meta, @{$$block[0]{poss}});

#	$string = _quote_file($string) if $block->[0]{_file_quote};
#	$string .= $block->[0]{postf} || ' ' if $winner && $string =~ m#\w$#; # FIXME not transparent !!

}

sub _get_last_block {
	my ($self, $string) = @_;

	# get block (last block) and words
	my @words;
	my ($block) = reverse $self->{parent}{stringparser}->split('script_gram', $string);
	if ($block && ref $block) {
		$block = $$block;
		@words = grep {length $_} 
			$self->{parent}{stringparser}->split('word_gram', $block);
	}
	else { $block = '' }
	push @words, '' if $block =~ /\s$/;

	# parse block
	$block = scalar(@words) # if @words == 1 the word could be for example env
		? $$self{parent}->parse_block([{string => $block}, @words], undef, 'PRETEND')
		: [{context => '_WORDS', string => $block}, ''] ;
	@{$$block[0]}{'poss', 'pref'} = ([], '');
	$$block[0]{context} ||= '_WORDS';

	# get words right
	# FIXME what to do with {start} ?
	if (exists $$block[0]{end} and @{$$block[0]{end}}) {
		$$block[0]{context} = 'SH';
		push @$block, @{$$block[0]{end}};
	}
	elsif (@$block == 1) { push @$block, '' } # empty string

	# get pref right
	unless ($string =~ s/\Q$$block[-1]\E$//) {
		my @words = $self->{parent}{stringparser}->split(
			['word_gram', {no_esc_rm => 1}], $$block[0]{string} );
		$string =~ s/\Q$words[-1]\E$//;
	}

	return ($string, $block);
}

sub join_blocks {
	my ($self, @blocks) = @_;
	@blocks = grep {scalar @{$$_[0]{poss}}} @blocks;
	return $blocks[0] || [{poss => []},''] if @blocks < 2;
	my @poss = map {
		my $b = $_;
		( map {$$b[0]{prefix}.$_} @{$$b[0]{poss}} )
	} @blocks;
	shift @{$blocks[0]};
	return [{poss => \@poss}, @{$blocks[0]}];
}

sub do {
	my ($self, $block, $try, @try) = @_;
	debug "gonna try $try (".'i_'.lc($try).")";
	return $block unless $try;
	my @re;
	if (ref($try) eq 'CODE') { @re = $try->($self, $block) }
	elsif (exists $self->{parent}{contexts}{$try}{intel}) {
		@re = $self->{parent}{contexts}{$try}{intel}->($block)
	}
	elsif ($self->can('i_'.lc($try))) {
		my $sub = 'i_'.lc($try);
		@re = $self->$sub($block);
	}
	else {
		debug $try.': no such expansion available';
	}

	if (defined $re[0]) { ($block, @try) = (@re, @try) }
	else { return @try ? $self->do($block, @try) : $block } # recurs

	my $succes = 0;
	if (ref($$block[0]) eq 'ARRAY') {
		$succes++ if grep {$$_[0]{poss} && @{$$_[0]{poss}}} @{$block}
	}
	else { $succes++ if $$block[0]{poss} && @{$$block[0]{poss}} }

	if ($succes) { return $block }
	else { return scalar(@try) ? $self->do($block, @try) : $block } # recurs
}

sub i_perl { return ($_[1], qw/_zoid env_vars dirs_n_files/) }

sub i__zoid {
	my ($self, $block) = @_;

	return undef if $block->[0]{opts} =~ /z/; # FIXME will fail when default opts are used
	return undef unless
		$block->[-1] =~ /^( (?:\$shell)? ( (?:->|->|\xA3) (?:\S+->)* (?:[\[\{].*?[\]\}])* )) (\S*)$/x;
	my ($pref, $code, $arg) = ($1, $2, qr/^\Q$3\E/);

	$code = '$self->{parent}' . $code;
	$code =~ s/\xA3/->/;
	$code =~ s/->$//;
	my $ding = eval($code);
	debug "$ding resulted from code: $code";
	my $type = ref $ding;
	if ($@ || ! $type) {
		$$block[0]{message} = $@ if $@;
		return $block;
	} 
	else { $block->[0]{prefix} .= $pref }

	my @poss;
	if ($type eq 'HASH') { push @poss, sort grep m/$arg/, map {'{'.$_.'}'} keys %$ding }
	elsif ($type eq 'ARRAY') { push @poss, grep m/$arg/, map {'['.$_.']'} (0 .. $#$ding) }
	elsif ($type eq 'CODE' ) { $block->[0]{message} = "\'$pref\' is a CODE reference"   } # do nothing (?)
	else { # $ding is object
		if ( $type eq ref $$self{parent} and ! $$self{parent}{settings}{naked_zoid} ) {
			# only display clothes
			debug 'show zoid clothed';
			push @poss, grep m/$arg/, @{ $$self{parent}->list_vars    };
			push @poss, grep m/$arg/, @{ $$self{parent}->list_clothes };
			push @poss, grep m/$arg/, @{ $$self{parent}->list_objects };
			$block->[0]{postf} = '->';
		}
		else {
			if (UNIVERSAL::isa($ding, 'HASH')) {
				push @poss, sort grep m/$arg/, map {'{'.$_.'}'} keys %$ding
			}
			elsif (UNIVERSAL::isa($ding, 'ARRAY')) {
				push @poss, grep m/$arg/, map {'['.$_.']'} (0 .. $#$ding)
			}

			unless ($arg =~ /[\[\{]/) {
				no strict 'refs';
				my @isa = ($type);
				my @m_poss;
				while (my $c = shift @isa) {
					push @m_poss, grep  m/$arg/, _subs($c);
					debug "class $c, ISA ", @{$c.'::ISA'};
					push @isa, @{$c.'::ISA'};
				}
				push @poss, @m_poss;
				$block->[0]{postf} = '(';
			}
		}
	}

	@poss = grep {$_ !~ /^\{?_/} @poss
		if $$self{parent}{settings}{hide_private_method} && $arg !~ /_/;
	$block->[0]{poss} = \@poss;
	return $block;
}

sub _subs { 
	no strict 'refs';
	grep defined *{"$_[0]::$_"}{CODE}, keys %{"$_[0]::"};
}

sub i__words { # to expand the first word
	my ($self, $block) = @_;

	my $arg = $block->[-1];
	push @{$block->[0]{poss}}, grep /^\Q$arg\E/, keys %{$self->{parent}{aliases}};
	push @{$block->[0]{poss}}, grep /^\Q$arg\E/, keys %{$self->{parent}{commands}};
	push @{$block->[0]{poss}}, grep /^\Q$arg\E/, list_path() unless $arg =~ m#/#;

	my @blocks = ($self->i_dirs_n_files($block, 'x'));
	my @alt;
	for (_stack($$self{parent}{contexts}, 'word_list')) {
		my @re = $_->($block);
		unless (@re) { next }
		elsif (ref $re[0]) {
			push @blocks, shift @re;
			push @alt, @re;
		}
		else { push @{$block->[0]{poss}}, grep {defined $_} @re }
	}
	push @blocks, $block;

	return (\@blocks, @alt);
}

sub i__end { i_dirs_n_files(@_) } # to expand after redirections

sub i_sh { return $_[1], ($_[1]->[-1] =~ /^-/) ? 'man_opts' : 'cmd' }

sub i_cmd {
	my ($self, $block) = @_;
	my @exp = qw/env_vars dirs_n_files/;
	if (exists $self->{config}{commands}{$$block[1]}) { # FIXME non compat with dispatch table
		my $exp = $self->{config}{commands}{$$block[1]};
		unshift @exp, ref($exp) ? (@$exp) : $exp;
	}
	return $block, @exp;
}

sub i_env_vars {
	my ($self, $block) = @_;
	return undef unless $$block[-1] =~ /^(.*[\$\@])(\w*)$/;
	$$block[0]{prefix} .= $1;
	$$block[0]{poss} = $2 ? [ grep /^$2/, keys %ENV ] : [keys %ENV];
	return $block;
}

sub i_dirs { i_dirs_n_files(@_, 'd') }
sub i_files { i_dirs_n_files(@_, 'f') }
sub i_exec { i_dirs_n_files(@_, 'x') }

sub i_dirs_n_files { # types can be x, f, ans/or d # TODO globbing tab :)
	my ($self, $block, $type) = @_;
	$type = 'df' unless $type;

	my $arg = $block->[-1];
	if ($arg =~ s/^(.*?(?<!\\):|\w*(?<!\\)=)//) { # /usr/bin:/<TAB> or VAR=<TAB>
		$$block[0]{prefix} .= $1 unless $$block[0]{i_dirs_n_files};
	}
	$arg =~ s#\\##g;

	my $dir;
	if ($arg =~ m#^~# && $arg !~ m#/#) { # expand home dirs
		return unless $type =~ /d/;
		push @{$$block[0]{poss}}, grep /^\Q$arg\E/, map "~$_/", list_users();
		$$block[0]{_file_quote}++;
		return $block;
	}
	else {
		if ($arg =~ s!^(.*/)!!) { 
			$dir = abs_path($1);
			$block->[0]{prefix} .= _quote_file($1)
				unless $block->[0]{i_dirs_n_files}++;
		}
		else { $dir = '.' }
		return undef unless -d $dir;
	}
	debug "Expanding files ($type) from dir: $dir with arg: $arg";

	my (@f, @d, @x);
	for (grep /^\Q$arg\E/, list_dir($dir)) {
		(-d "$dir/$_") ? (push @d, $_) :
			(-x _) ? (push @x, $_) : (push @f, $_) ;
	}
	
	my @poss = ($type =~ /f/) ? (sort @f, @x) : ($type =~ /x/) ? (@x) : ();
	unshift @poss, map $_.'/', @d;

	@poss = grep {$_ !~ /^\./} @poss
		if $$self{parent}{settings}{hide_hidden_files} && $arg !~ /^\./;

	$$block[0]{_file_quote}++;
	push @{$$block[0]{poss}}, @poss;

	return $block;
}

sub _quote_file { 
	my $string = shift;
	$string =~ s#([\[\]\(\)\s\?\!\#\&\|\;\:\"\'\{\}])#\\$1#g;
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
	return unless $$self{config}{man_cmd} && $$block[1];
	debug "Going to open pipeline '-|', '$$self{config}{man_cmd}', '$$block[1]'";

	# re-route STDERR
	open SAVERR, '>&STDERR';
	open STDERR, '>', $Zoidberg::Utils::FileSystem::DEVNULL;

	# reset manpager
	local $ENV{MANPAGER} = 'cat'; # FIXME is this portable ?

	open MAN, '-|', $$self{config}{man_cmd}, $$block[1];
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
	
	$block->[0]{poss} = [ grep /^\Q$$block[-1]\E/, sort keys %poss ];
	if (@{$$block[0]{poss}} == 1) { $$block[0]{message} = ${$poss{$$block[0]{poss}[0]}} }
	elsif (exists $poss{$$block[-1]}) { $$block[0]{message} = ${$poss{$$block[-1]}} }
	$block->[0]{message} =~ s/[\s\n]+$//; #chomp it

	return $block;
}

1;

__END__

=head1 NAME

Zoidberg::Fish::Intel - Completion plugin for Zoidberg

=head1 SYNOPSIS

This module is a Zoidberg plugin, see Zoidberg::Fish for details.

=head1 DESCRIPTION

This class provides intelligence for tab-expansion
and similar functions. It is very dynamic structured.

=head2 EXPORT

None by default.

=head1 METHODS

FIXME

=head2 Build-in expansions

FIXME

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Fish>,
L<http://zoidberg.sourceforge.net>

=cut


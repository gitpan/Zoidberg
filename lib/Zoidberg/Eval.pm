package Zoidberg::Eval;

our $VERSION = '0.3a_pre1';

use strict;
use vars qw/$AUTOLOAD/;

use Data::Dumper;
use File::Glob ':glob';
use Zoidberg::Error;
use Zoidberg::FileRoutines qw/:exec_scope is_exec_in_path/;
use Zoidberg::Shell qw/:exec_scope/;

our @PATH;
our $DEBUG = 0;
export(\@PATH => 'PATH');

$| = 1;

sub _new {
	my $class = shift;
	my $self = {};
	$self->{zoid} = shift; # this will be $self for eval blocks
	bless $self, $class;
}

sub _eval_block {
	my ($self, $block) = @_;
	my $meta = shift @{$block};
	my $context = $meta->{context};
	
	my $orig_ref = $ENV{ZOIDREF};
	$ENV{ZOIDREF} = $self;

	eval {
		# TODO check plugin contexts
		if ($self->can('_do_'.lc($context))) {
			my $sub = '_do_'.lc($context);
			print "debug: going to call sub: $sub,\nblock: ", Dumper $block if $DEBUG;
			$self->$sub($block, $meta);
		}
		else { error qq/No handler defined for context $context\n/ }
	};
	
	$ENV{ZOIDREF} = $orig_ref if defined $orig_ref;

	if ($@) {
		$self->{exec_error} = $@;
		$self->{zoid}->print_error($@);
	}
	else { undef $self->{exec_error} }

}

=for begin comment

The  nice  and simple rule given above: `expand a wildcard pattern into
the list of matching pathnames' was the original  Unix  definition. It
allowed one to have patterns that expand into an empty list, as in
xv -wait 0 *.gif *.jpg where  perhaps  no  *.gif files are present 
(and this is not an error). However, POSIX requires that a wildcard 
pattern is left unchanged  when it  is  syntactically  incorrect,  
or the list of matching pathnames is empty.  With bash one can force  
the  classical  behaviour  by  setting allow_null_glob_expansion=true.

So the setting allow_null_glob_expansion should switch of GLOB_NOCHECK

=end comment

=cut

sub _do_sh {
	my ($self, $block, $meta) = @_;
	my @r;

	# path expansion
	unless ($self->{zoid}{settings}{noglob}) {
		my $glob_opts = GLOB_MARK|GLOB_TILDE|GLOB_BRACE|GLOB_QUOTE;
		$glob_opts |= GLOB_NOCHECK unless $self->{zoid}{settings}{allow_null_glob_expansion};
		@r = map { bsd_glob($_, $glob_opts) } @{$block} ;
	}
	else { @r = @{$block} }

	print "debug: going to exec : ", Dumper \@r if $DEBUG;

	_check_exec($r[0]) unless $meta->{_is_checked};

	$self->{zoid}{_} = $r[-1]; # useless in fork (?)
	if ($self->{zoid}->{round_up}) { system(@r); }
	else { exec {$r[0]} @r; }
}

sub _check_exec {
	# arg 0 is executable when this sub doesn't die
	if ($_[0] =~ m|/|) {
		error $_[0].': No such file or directory' unless -e $_[0];
		error $_[0].': is a directory' if -d $_[0];
		error $_[0].': Permission denied' unless -x $_[0];
	}
	elsif (! is_exec_in_path($_[0])) { error $_[0].': command not found' }
}

sub _do_cmd {
	my ($self, $block, $meta) = @_;
	my $cmd = shift @{$block};
	error qq(No such command: $cmd\n) unless $self->_is_cmd($cmd);
	return $self->{zoid}{commands}{$cmd}->(@{$block});
}

sub _is_cmd { exists $_[0]->{zoid}{commands}{$_[1]} }

sub _do_perl {
	my ($_Eval, $_Block, $_Meta) = @_;
	my $_Code = $_Eval->_dezoidify($_Block->[0]);
	$_Code = $_Eval->_parse_opts($_Code, $_Meta->{opts});
	print "debug: going to eval perl code: -->no strict; $_Code<--\n"  if $DEBUG;

	my $self = $_Eval->{zoid};
	$_ = $self->{_};
	
	eval('no strict; '.$_Code); # TODo, what about the return value ?  # FIXME make strict an option
        die if $@; # should we check $! / $? / $^E here ?
	
        $self->{_} = $_;
	 print "\n"; # ugly hack
}

our $_Zoid_gram = {
# The original regexp:
# ((?<![\\w\\}\\)\\]])->|\\xA3)([\\{]?\\w+[\\}]?)
	esc => qr/[\\\w\}\)\]]/,
	tokens => [
		[ qr/->/,   'ARR' ], # ARRow
		[ qr/\xA3/, 'MCH' ], # Magic CHar
	],
};

sub _dezoidify {
	my ($self, $code) = @_;
	my $p = $self->{zoid}{StringParser};
	$p->set($_Zoid_gram, $code);
	my ($n_code, $block, $token, $prev_token, $thing);
	while ($p->more) { #print 'n code: ', $n_code, "\n";
		$prev_token = $token;
		($block, $token) = $p->get;
 
		unless (defined $n_code) { $n_code = $block; next }
		$n_code .= '->'.$block and next unless $thing = ($block =~ /^(\{?\w+\}?)/);

		if ($self->{zoid}{settings}{naked_zoid} && ($prev_token ne 'MCH') ) { $n_code = '$self->'.$block }
		elsif (grep {$_ eq $thing} @{$self->{zoid}->list_clothes}) { $n_code = '$self->'.$block }
		elsif ($thing =~ m|^\{|) { $n_code = '$self->{vars}'.$block } # is this still usefull ?
		else { 
			$block =~ s/^(\w+)/\$self->object('$1')/;
			$n_code .= $block;
		}
	}
	return $n_code;
}

sub _parse_opts { # parse switches
	my ($self, $string, $opts) = @_;

	# TODO if in pipeline set 'n' as defult unless 'N'

	if ($opts =~ m/g/) { $string = "\nwhile (<STDIN>) {\n\tif (eval {".$string."}) { print \$_; }\n}"; }
	elsif ($opts =~ m/p/) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n\tprint \$_\n}"; }
	elsif ($opts =~ m/n/) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n}"; }

#	if ($opts =~ m/b(\d+)/) {
#		$string = qq{ \$self->print(
#	Benchmark::timestr(Benchmark::timethis($1, sub{
#		$string
#	},'','none'))) };
#	}

	return $string;
}

sub AUTOLOAD {
	## Code inspired by Shell.pm -- but rewrote it
	
	my $self;
	if (ref($_[0]) eq 'Zoidberg::Eval') { $self = shift }
	else { $self = $ENV{ZOIDREF} }

	my @args = @_;
	my $cmd = (split/::/,$AUTOLOAD)[-1];

	return undef if $cmd eq 'DESTROY';
	print "debug: autoload got command: $cmd\n" if $DEBUG;

	if ($self->_is_cmd($cmd)) { $self->_do_cmd([$cmd, @args]) }
	else { # system
		_check_exec($cmd);
		open CMD, '-|', $cmd, @_;
		my @ret = (<CMD>);
		close CMD;
		$self->{exec_error} = $?;
		if (wantarray) { return map {chomp; $_} @ret; }
		else { return join('',@ret); }
	}
}

=begin old

sub _Eval_block {
	my $_Eval = shift;
	my ($_String,$_Context,$_Opts) = @_;

	my $self = $_Eval->{zoid}; # $self ain't always what it appears to be
	$self->print("Zoidberg::Eval->_Eval_block('".join("', '", @_[0..2])."')",'debug');
	my $_Code = q|$self->print("Could not found a parser for \"$_Context\"", 'error');|;
	my @_Bits = (0,0,1);
	my @_Args = ();
	if (ref($_String) eq 'ARRAY') {  # FIXME temporary hack -- this is evil
		@_Args = @{$_String};
		$_String = shift @_Args;
	}
	# Bits: not_interpolate_pound, not_parse_opts, do_command_syntax
	if (ref($self->{grammar}{context}{$_Context}) && $self->{grammar}{context}{$_Context}[0]) {
		my $sub = $self->{grammar}{context}{$_Context}[0];
		if (ref($self->{grammar}{context}{$_Context}[2])) { @_Bits = @{$self->{grammar}{context}{$_Context}[2]}; }
		$sub =~ s/^->//;
		if ($sub =~ s/(\(.*\))\s*$//) { @_Args = eval($1); }
		if ($_Bits[2]) {
			if ($_Bits[1]) { $_Code = qq|\$self->$sub([\@_Args], \$_Opts);| }
			else { $_Code = qq|\$self->$sub(\@_Args);| }
		}
		else { $_Code = qq|\$self->$sub(\@_Args, \$_String|.($_Bits[1] ? q|, \$_Opts);| : ');') }
	}
	elsif (($_Context eq 'PERL')||($_Context eq 'ZOID')) {
		chomp $_String;
		$_Code = $_Eval->_perlify($_String);
		if ($_Context eq 'PERL') { $_Code = 'no strict; '.$_Code; } # TODO make configable
		@_Bits = (1,0,0);
	}
	elsif (($_Context eq 'SYSTEM')||($_Context eq 'COMMAND')) {
		#$_Code = q|$_Eval->_system(@_Args)|;
		$_Code = $_String;
		@_Bits = (0,1,1);
	}

#	if ($_Bits[2]) { # command syntax
#		unless ($_Bits[0]) { push @_Args, map {$_Eval->_interpolate($_)} $_Eval->_parse_command($_String); }
#		else { push @_Args, $_Eval->_parse_command($_String); }
#	}
#	elsif 
	if (!$_Bits[0]) { $_Code = $_Eval->_interpolate($_Code); }

	unless ($_Bits[1]) { $_Code = $_Eval->_parse_opts($_Code, $_Opts); }
	$self->print("Going to eval '$_Code'", "debug");
	$self->print("Array _Args is ".join(', ', map {s/([\\'])/\\$1/g; qq{'$_'}} @_Args), "debug") if @_Args;

	my $_Self_orig = $_Self if defined $_Self;
	$_Self = $_Eval; # Hack alert
	# restoring original value should make nested evals with different objects possible

	$_ = $self->{_};
	$self->{exec_error} = [grep {$_} eval($_Code)];
	$self->{_} = $_;
	# FIXME lot more error types from perl code should be in use
	# 	to get return types good, eval perl and eval sub need to differ ...
	$_Self = $_Self_orig if defined $_Self_orig;

	if ($@) { # FIXME error message should include line num in some cases
		my $er = $@;
		chomp $er;
		push @{$self->{exec_error}}, $er;
	}

	if ($_Context eq 'PERL') { print "\n"; } # ranzige hack
	$self->print( $self->{exec_error}, 'error') if @{$self->{exec_error}};
	# FIXME ERROR - this should be on a higher level # FIXME why is @{[0]} true ??/

	return $self->{exec_error};
}

sub _parse_command { # parse sh like syntax to array args
	my $self = shift;
	my $string = shift;
	$string =~ s/\A\s*//gm ; # TODO deze regex in stringparse
	my @args = map {$_->[0]} @{$self->{zoid}->{StringParser}->parse($string,'space_gram')};
	while ((@args) && $args[-1] eq '') { pop @args; } # ranzige hack
	$self->{zoid}->print("Command args: '".join("', '", @args)."'", 'debug');
	return @args;
}

sub _perlify { # fully qualify -> and pound syntax
	my $self = shift;
	my $string = shift;
	my $tree = $self->{zoid}{StringParser}->parse($string,'eval_zoid_gram');
	#print "debug ".Dumper($tree);
	foreach my $i (0 .. $#{$tree}) {
		my $ref = $tree->[$i];
		#<ERUG-VUNZIG>
		if ($ref->[0]) { if ($ref->[0] =~ /[\w\}\)\]]$/) {next } }
		elsif ($tree->[$i-1][1] =~ /[\w\}\)\]]$/) { next }
		#</ERUG-VUNZIG>
		if ($ref->[1] eq "\xA3_") { $ref->[1] = '$self->{_}'}
		elsif ($ref->[1] =~ s/^(->|\xA3)//) {
			if ($self->{zoid}{settings}{naked_zoid} && ($1 ne "\xA3")) { $ref->[1] = '$self->'.$ref->[1]; }
			elsif (grep {$_ eq $ref->[1]} @{$self->{zoid}->list_clothes}) { $ref->[1]='$self->'.$ref->[1]; }
			elsif ($ref->[1] =~ m|^\{(\w+)\}$|) { $ref->[1] = '$self->{vars}'.$ref->[1]; }
			else { $ref->[1] = '$self->object(\''.$ref->[1].'\')' }
		}
	}
	$string = join('', map {$_->[0].$_->[1]} @{$tree});
	return $string;
}

sub _interpolate { # substitutes pound vars with their values
	# TODO fine tuning and grinding
	my $self = shift;
	my $string = shift;
	#if ($string =~ /^(\$|\xA3)_$/) { $string = \$self->{zoid}{_}; }
	#else {

		my $tree = $self->{zoid}{StringParser}->parse($string,'eval_zoid_gram');
		print "debug ".Dumper($tree);
		foreach my $i (0 .. $#{$tree}) {
		#	if ($tree->[$i-1][0] =~ /[\w\}\)\]]$/) { next }
			$ref = $tree->[$i];
			if ($ref->[1] eq "\xA3_") { $ref->[1] = $self->{zoid}{_}}
			elsif ($ref->[1] =~ s/^(->|\xA3)//) { # Vunzige implementatie -- moet via stringparse strakker
				if ($self->{zoid}{settings}{naked_zoid} && ($1 ne "\xA3")) { $ref->[1] = eval('$self->{zoid}->'.$ref->[1]); }
				elsif (grep {$_ eq $ref->[1]} @{$self->{zoid}->list_clothes}) { $ref->[1] = eval('$self->{zoid}->'.$ref->[1]); }
				elsif ($ref->[1] =~ m|^\{(\w+)\}$|) { $ref->[1] = eval('$self->{zoid}{vars}->'.$ref->[1]); }
				else { $ref->[1] = eval('$self->{zoid}->objects(\''.$ref->[1].'\')') }
			}
		}
		$string = join('', map {$_->[0].$_->[1]} @{$tree});

	#}
	return $string;
}


=end old

=cut

1;

__END__


=head1 NAME

Zoidberg::Eval

=head1 DESCRIPTION

This module is intended for internal use only.
See L<Zoidberg::ZoidParse>.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


package Zoidberg::Eval;

our $VERSION = '0.41';

use strict;
use vars qw/$AUTOLOAD/;

use Data::Dumper;
use File::Glob qw/:glob/;
use Zoidberg::Shell qw/:all/;
use Zoidberg::Utils qw/:error :output :fs is_exec_in_path/;

our %_REFS; # stores refs to objects of this class for ipc use

$| = 1;

sub _new { bless { zoid => $_[1] }, $_[0] }

sub _eval_block {
	my ($self, $ref) = @_;
	my $context = $$ref[0]{context};

	if (
		exists $self->{zoid}{contexts}{$context} and
		exists $self->{zoid}{contexts}{$context}{handler}
	) {
		debug "going to call handler for context: $context";
		$self->{zoid}{contexts}{$context}{handler}->(@$ref);
	}
	elsif ($self->can('_do_'.lc($context))) {
		my $sub = '_do_'.lc($context);
		debug "going to call sub: $sub";
		$self->$sub(@$ref);
	}
	else {
		$context
			? error "No handler defined for context $context"
			: bug   'No context defined !'
	}
}

=cut

The  nice  and simple rule given above: `expand a wildcard pattern into
the list of matching pathnames' was the original  Unix  definition. It
allowed one to have patterns that expand into an empty list, as in
xv -wait 0 *.gif *.jpg where  perhaps  no  *.gif files are present 
(and this is not an error). However, POSIX requires that a wildcard 
pattern is left unchanged  when it  is  syntactically  incorrect,  
or the list of matching pathnames is empty.  With bash one can force  
the  classical  behaviour  by  setting allow_null_glob_expansion=true.

So the setting allow_null_glob_expansion should switch of GLOB_NOCHECK

=cut

our @_shell_expand = qw/_expand_param _expand_path/;

sub _do_sh {
	my ($self, $meta, @words) = @_;

	$ENV{_} = $self->{zoid}{topic};
	@words = $self->$_(@words) for @_shell_expand;
	_check_exec($words[0]) unless $$meta{_is_checked};
	$self->{zoid}{topic} = $words[-1]; # FIXME we are in fork allready here :(
	debug 'going to run: ', join ', ', @words;

	if ($self->{zoid}{round_up}) { system @words }
	else { exec {$words[0]} @words }
}

sub _do_cmd {
	my ($self, $meta, @words) = @_;

	@words = $self->$_(@words) for @_shell_expand;
	my $cmd = shift @words;
	$self->{zoid}{topic} = $words[-1]; # FIXME check this

	debug 'going to run cmd: ', join ', ', $cmd, @words;
	local $Zoidberg::Utils::Error::Scope = $cmd;
#	no strict 'refs';
#	if (defined *{ref($self).'::'.$cmd}{CODE}) {
#		return output &{ref($self).'::'.$cmd}->(@$block);
#	}
#	elsif (exists $self->{zoid}{commands}{$cmd}) {
	if (exists $self->{zoid}{commands}{$cmd}) {
		return $self->{zoid}{commands}{$cmd}->(@words);
	}
	else { error qq(No such command: $cmd\n) }
}

sub _expand_param {
	my ($self, @words) = @_;
	for (@words) {
		# TODO array indices -- see man bash -- think Env.pm
		next if /^'.*'$/;
		s{ (?<!\\) \$ (?: \{ (.*?) \} | (\w+) ) (?: \[(\d+)\] )? }{
			my ($w, $i) = ($1 || $2, $3);
			error "no advanced expansion for \$\{$w\}" if $w =~ /\W/;
			$w = $ENV{$w};
			$i ? (split /:/, $w)[$i] : $w;
		}exg;
	}
	return map {
		if (m/^ \@ (?: \{ (.*?) \} | (\w+) ) $/x) {
			my $w = $1 || $2;
			error "no advanced expansion for \@\{$w\}" if $w =~ /\W/;
			split /:/, $ENV{$w};
		}
		else { $_ }
	} @words;
}

sub _expand_path { # path expansion
	my ($self, @files) = @_;
	unless ($self->{zoid}{settings}{noglob}) {
		my $glob_opts = GLOB_TILDE|GLOB_BRACE|GLOB_QUOTE;
		$glob_opts |= GLOB_NOCHECK unless $self->{zoid}{settings}{allow_null_glob_expansion};
		@files = map { /^['"](.*)['"]$/ ? $1 : bsd_glob($_, $glob_opts) } @files ;
	}
	else {  @files = map { /^['"](.*)['"]$/ ? $1 : $_ } @files  }
	return @files;
}

sub _check_exec {
	# arg 0 is executable when this sub doesn't die
	debug "checking $_[0]";
	if ($_[0] =~ m|/|) {
		error $_[0].': No such file or directory' unless -e $_[0];
		error $_[0].': is a directory' if -d $_[0];
		error $_[0].': Permission denied' unless -x $_[0];
	}
	elsif (! is_exec_in_path($_[0])) { error $_[0].': command not found' }
	debug 'approved';
	return 1;
}

sub _do_perl {
	my ($_Eval, $_Meta, $_Code) = @_;
	$_Code = $_Eval->_dezoidify($_Code) if $_Meta->{dezoidify};
	$_Code = $_Eval->_parse_opts($_Code, $_Meta->{opts}) if $_Meta->{opts};
	debug 'going to eval perl code: no strict; '.$_Code;

	my $shell = $_Eval->{zoid};
	$_ = $shell->{topic};

	local $Zoidberg::Utils::Error::Scope = ['zoid', 0];
	eval 'no strict; '.$_Code; # FIXME make strict an option
        die if $@; # should we check $! / $? / $^E here ?

        $shell->{topic} = $_;
	print "\n" if $shell->{settings}{interactive}; # ugly hack
}

sub _interpolate_magic_char {
	my ($self, $string) = @_;
	$string =~ s/(?<!\\)\xA3\{(\w+)\}/$self->{zoid}{vars}{$1}/eg;
	$string =~ s/\\(\xA3)/$1/g;
	return $string;
}

our $_Zoid_gram = {
	tokens => [
		[ qr/->/,   'ARR' ], # ARRow
		[ qr/\xA3/, 'MCH' ], # Magic CHar
	],
	nests => {},
	no_esc_rm => 1,
};

sub _dezoidify {
	my ($self, $code) = @_;
	
	## environment variables
	#$code =~ s/\$([A-Z_]+)(?![\{\[\w])/\$ENV{$1}/g;
	# TODO arrays
	# TODO unless $1 eq ENV || SIG || ..

	## arrow syntax
	my $p = $self->{zoid}{stringparser};
	$p->set($_Zoid_gram, $code);
	my ($n_code, $block, $token, $prev_token, $thing);
	while ($p->more) { 
		$prev_token = $token;
		($block, $token) = $p->get;
#		print "code is -->$n_code<-- prev token -->$prev_token<--\ngot block -->$block<-- token -->$token<--\n";
 
		if (! defined $n_code) { $n_code = $block }
		elsif ($prev_token eq 'ARR' and $n_code =~ /[\w\}\)\]]$/) { $n_code .= '->'.$block }
		elsif (! (($thing) = ($block =~ /^(\w+|\{\w+\})/)) ) { $n_code .= '->'.$block }
		elsif (
			$self->{zoid}{settings}{naked_zoid} && ($prev_token ne 'MCH')
			or grep {$_ eq $thing} @{$self->{zoid}->list_clothes}
		) { $n_code .= '$shell->'.$block }
		elsif ($thing =~ /^\{/) { $n_code .= '$shell->{vars}'.$block }
		else {
			$block =~ s/^(\w+)/\$shell->{objects}{$1}/;
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

	return $string;
}

# ################# #
# Some hidden utils #
# ################# #

sub _dump_fish {
	my $ding = shift;
	my ($zoid, $parent);
	$ding->{zoid} = "$zoid" if $zoid = delete $ding->{zoid};
	$ding->{parent} = "$parent" if $parent = delete $ding->{parent};
#	print Dumper $ding;
	$ding->{zoid} = $zoid if defined $zoid;
	$ding->{parent} = $parent if defined $parent;
}

1;

=head1 NAME

Zoidberg::Eval - eval namespace

=head1 DESCRIPTION

This module is intended for internal use only.
It is the namespace for executing builtins and perl code, also
it contains some routines to execute builtin syntaxes.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Parser>, L<Zoidberg::Contractor>
L<http://zoidberg.sourceforge.net>

=cut


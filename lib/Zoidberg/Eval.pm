package Zoidberg::Eval;

our $VERSION = '0.53';

use strict;
use vars qw/$AUTOLOAD/;

use Data::Dumper;
use Zoidberg::Shell qw/:all/;
use Zoidberg::Utils qw/:error :output :fs/;
require Env;

$| = 1;

sub _new { bless { shell => $_[1] }, $_[0] }

sub _eval_block {
	my ($self, $ref) = @_;
	my $context = $$ref[0]{context};

	if (
		exists $self->{shell}{contexts}{$context} and
		exists $self->{shell}{contexts}{$context}{handler}
	) {
		debug "going to call handler for context: $context";
		$self->{shell}{contexts}{$context}{handler}->($ref);
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

sub _do_sh {
	my ($self, $meta, @words) = @_;
	if ($words[0] =~ m|/|) {
		error $words[0].': No such file or directory' unless -e $words[0];
		error $words[0].': is a directory' if -d _;
		error $words[0].': Permission denied' unless -x _;
	}
	debug 'going to run: ', join ', ', @words;

	# exec = exexvp which checks PATH allready
	# the block syntax to force use of execvp, not shell for one argument list
	exec {$words[0]} @words
		or error $words[0].': command not found';
}

sub _do_cmd {
	my ($self, $meta, $cmd, @args) = @_;
	debug 'going to run cmd: ', join ', ', $cmd, @args;
	local $Zoidberg::Utils::Error::Scope = $cmd;
	error qq(No such command: $cmd\n)
		unless exists $self->{shell}{commands}{$cmd};
	$self->{shell}{commands}{$cmd}->(@args);
}

sub _do_perl {
	my ($_Eval, $_Meta, $_Code) = @_;
	$_Code = $_Eval->_parse_opts($_Code, $_Meta->{opts});
	debug 'going to eval perl code: '.$_Code;

	my $shell = $_Eval->{shell};
	
	local $Zoidberg::Utils::Error::Scope = ['zoid', 0];
	$_ = $shell->{topic};
	eval $_Code;
	if ($@) { # post parse errors 'n stuff
		die if ref $@; # just propagate the exception
		$@ =~ s/ at \(eval \d+\) line (\d+)(\.|,.*\.)$/ at line $1/;
		error { string => $@, scope => [] };
	}
	else { 
		$shell->{topic} = $_;
		print "\n" if $shell->{settings}{interactive}; # ugly hack
	}
}

sub _interpolate_magic_char {
	my ($self, $string) = @_;
	$string =~ s/(?<!\\)\xA3\{(\w+)\}/$self->{shell}{vars}{$1}/eg;
	$string =~ s/\\(\xA3)/$1/g;
	return $string;
}

sub _parse_opts { # parse switches
	my ($self, $string, $opts) = @_;
	my %opts = map {($_ => 1)} split '', $opts;
	debug 'options: ', \%opts;

	$string = $self->_dezoidify($string) unless $opts{z};

	if ($opts{g}) { $string = "\nwhile (<STDIN>) {\n\tif (eval {".$string."}) { print \$_; }\n}"; }
	elsif ($opts{p}) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n\tprint \$_\n}"; }
	elsif ($opts{n}) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n}"; }

	$string = 'no strict; '.$string unless $opts{z};

	return $string;
}

our $_Zoid_gram = {
	tokens => [
		[ qr/->/,   'ARR' ], # ARRow
		[ qr/\xA3/, 'MCH' ], # Magic CHar
		[ qr/[\$\@][A-Za-z_][\w\-]*(?<!\-)/, '_SELF' ], # env var
	],
	quotes => { "'" => "'" }, # interpolate also between '"'
	nests => {},
	no_esc_rm => 1,
};

sub _dezoidify {
	my ($self, $code) = @_;
	
	my $p = $self->{shell}{stringparser};
	$p->set($_Zoid_gram, $code);
	my ($n_code, $block, $token, $prev_token, $thing);
	my $i = 1;
	while ($p->more) { 
		$prev_token = $token;
		($block, $token) = $p->get;
#print "code is -->$n_code<-- prev token -->$prev_token<--\ngot block -->$block<-- token -->$token<--\n";
 
		LAST:	
		if (! defined $n_code) { $n_code = $block }
		elsif ($prev_token =~ /^([\@\$])(\w+)/) {
			my ($s, $v) = ($1, $2);
			if (
				$block =~ /^::/
				or grep {$v eq $_} qw/_ ARGV ENV SIG INC/
				or ( $v =~ /[a-z]/ and ! exists $ENV{$v} )
			) { $n_code .= $s.$v.$block} # reserved or non-env var
			elsif ($s eq '@' or $block =~ /^\[/) { # array
				no strict 'refs';
				unless (defined *{$v}{ARRAY} and @{$v}) {
					Env->import('@'.$v);
					debug "imported \@$v from Env";
				}
				$n_code .= $s.$v.$block;
			}
			else { $n_code .= '$ENV{'.$v.'}'.$block } # scalar or hash deref
		}
		elsif ($prev_token eq 'ARR' and $n_code =~ /[\w\}\)\]]$/) { $n_code .= '->'.$block }
		elsif (! (($thing) = ($block =~ /^(\w+|\{\w+\})/)) ) { $n_code .= '->'.$block }
		elsif (
			$self->{shell}{settings}{naked_zoid} && ($prev_token ne 'MCH')
			or grep {$_ eq $thing} @{$self->{shell}->list_clothes}
		) { $n_code .= '$shell->'.$block }
		elsif ($thing =~ /^\{/) { $n_code .= '$shell->{vars}'.$block }
		else {
			$block =~ s/^(\w+)/\$shell->{objects}{$1}/;
			$n_code .= $block;
		}
	}
	if ($i-- && defined $token) { # one more iteration please
		$prev_token = $token;
		$block = undef;
		goto LAST;
	}
	return $n_code;
}

# ################# #
# Some hidden utils #
# ################# #

sub _dump_fish {
	my $ding = shift;
	my ($zoid, $parent);
	$ding->{shell} = "$zoid" if $zoid = delete $ding->{shell};
	$ding->{parent} = "$parent" if $parent = delete $ding->{parent};
#	print Dumper $ding;
	$ding->{shell} = $zoid if defined $zoid;
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


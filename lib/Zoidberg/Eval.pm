package Zoidberg::Eval;

our $VERSION = '0.90';

use strict;
use vars qw/$AUTOLOAD/;

use Data::Dumper;
use Zoidberg::Shell qw/:all/;
use Zoidberg::Utils qw/:error :output :fs regex_glob/;
require Env;

$| = 1;
$Data::Dumper::Sortkeys = 1;

sub _new { bless { shell => $_[1] }, $_[0] }

sub _eval_block {
	my ($self, $ref) = @_;
	my $context = $$ref[0]{context};

	if (
		exists $$self{shell}{parser}{$context} and
		exists $$self{shell}{parser}{$context}{handler}
	) {
		debug "going to call handler for context: $context";
		$self->{shell}{parser}{$context}{handler}->($ref);
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

sub _do_subz { # sub shell, forked if all is well
	my ($self, $meta) = @_;
	my $cmd = $$meta{zoidcmd};
	$cmd = $1 if $cmd =~ /^\s*\((.*)\)\s*$/s;
	%$meta = map {($_ => $$meta{$_})} qw/env/; # FIXME also add parser opts n stuff
	# FIXME reset mode n stuff ?
	$self->{shell}->shell_string($meta, $cmd);
	error $$self{shell}{error}
		if $$self{shell}{error};
}

sub _do_cmd {
	my ($self, $meta, $cmd, @args) = @_;
	# exec = exexvp which checks PATH allready
	# the block syntax to force use of execvp, not shell for one argument list
	$$meta{cmdtype} ||= '';
	if ($cmd =~ m|/|) { # executable file
		error 'builtin should not contain a "/"' if $$meta{cmdtype} eq 'builtin';
		error $cmd.': No such file or directory' unless -e $cmd;
		error $cmd.': is a directory' if -d _;
		error $cmd.': Permission denied' unless -x _;
		debug 'going to exec file: ', join ', ', $cmd, @args;
		exec {$cmd} $cmd, @args or error $cmd.': command not found';
	}
	elsif ($$meta{cmdtype} eq 'builtin' or exists $$self{shell}{commands}{$cmd}) { # built-in, not forked I hope
		error $cmd.': no such builtin' unless exists $$self{shell}{commands}{$cmd};
		debug 'going to do built-in: ', join ', ', $cmd, @args;
		local $Zoidberg::Utils::Error::Scope = $cmd;
		$$self{shell}{commands}{$cmd}->(@args);
	}
	else { # command in path ?
		debug 'going to exec: ', join ', ', $cmd, @args;
		exec {$cmd} $cmd, @args or error $cmd.': command not found';
	}
}

sub _do_perl {
	my ($_Eval, $_Meta, $_Code) = @_;
	debug 'going to eval perl code: '.$_Code;

	my $shell = $_Eval->{shell};
	
	local $Zoidberg::Utils::Error::Scope = ['zoid', 0];
	$_ = $shell->{topic};
	ref($_Code) ? eval { $_Code->() } : eval $_Code;
	if ($@) { # post parse errors
		die if ref $@; # just propagate the exception
		$@ =~ s/ at \(eval \d+\) line (\d+)(\.|,.*\.)$/ at line $1/;
		error { string => $@, scope => [] };
	}
	else { 
		$shell->{topic} = $_;
		print "\n" if $shell->{settings}{interactive}; # ugly hack
	}
}

{
	no warnings;
	sub AUTOLOAD {
		## Code inspired by Shell.pm ##
		my $cmd = (split/::/, $AUTOLOAD)[-1];
		return undef if $cmd eq 'DESTROY';
		shift if ref($_[0]) eq __PACKAGE__;
		debug "Zoidberg::Eval::AUTOLOAD got $cmd";
		@_ = ([$cmd, @_]); # force words
		unshift @{$_[0]}, '!'
			if lc( $Zoidberg::CURRENT->{settings}{mode} ) eq 'perl';
		goto \&shell;
	}
}

# ######### #
# Some util #
# ######### #

sub pp { # pretty print
	local $Data::Dumper::Maxdepth = shift if $_[0] =~ /^\d+$/;
	if (wantarray) { return Dumper @_ }
	else { print Dumper @_ }
}

1;

=head1 NAME

Zoidberg::Eval - Eval namespace

=head1 DESCRIPTION

This module is intended for internal use only.
It is the namespace for executing builtins and perl code, also
it contains some routines to execute builtin syntaxes.

=head1 METHODS

Some methods are prefixed with a '_' to keep the namespace as
clean as possible.

=over 4

=item _new($shell)

Simple contstructor.

=item _eval_block($block)

Eval (execute) a block.

=item pp($data)

"Pretty Print", a simple wrapper routine for L<Data::Dumper>.
If the first argument is an integer this is used as the maximum
recursion depth for the dump.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Parser>, L<Zoidberg::Contractor>

=cut


package Zoidberg::Shell;

our $VERSION = '0.40';

use strict;
use vars qw/$AUTOLOAD/;
use Carp;
use Zoidberg::Error;
use Zoidberg::FileRoutines qw/abs_path/;
use Zoidberg::Utils qw/:output/;
use Exporter::Tidy
	default	=> [qw/AUTOLOAD shell/],
	zoidrc	=> [qw/alias unalias set setting shell/],
	other	=> [qw/shell_string shell_tree  exec_error/];

# TODO unless ref($ENV{ZOIDREF}) start ipc

sub new {
	my ($class, $ref) = @_;
	unless ($ref) {
		return unless ref($ENV{ZOIDREF}); # make use_ok test happy :((
		$ref = $ENV{ZOIDREF};
	}
	bless {zoid => $ref}, $class;
}

sub _self { (ref($_[0]) eq __PACKAGE__) ? shift : {zoid => $ENV{ZOIDREF}} }

# ################ #
# Parser interface #
# ################ #

sub AUTOLOAD {
	## Code inspired by Shell.pm ##
	my $cmd = (split/::/, $AUTOLOAD)[-1];
	return undef if $cmd eq 'DESTROY';
	shift if ref($_[0]) eq __PACKAGE__;
	debug "Zoidberg::Shell::AUTOLOAD got $cmd";
	unshift @_, $cmd;
	goto \&shell;
}

sub shell {
	my $self = &_self;
	my $tree = [];
	unless (ref $_[0]) { @$tree = [ $self->{zoid}->parse_words({}, @_) ] }
	else { @$tree = map {ref($_) ? [$self->{zoid}->parse_words({}, @$_)] : $_ } @_ }
	$self->{zoid}->do_list($tree);
	# TODO use wantarray
}

sub shell_string { 
	my $self = &_self;
	$self->{zoid}->do(@_);
}

sub shell_tree { todo }

sub exec_error { 
	my $self = &_self;
	return $self->{zoid}{exec_error}
}

# ############# #
# Some builtins #
# ############# #

sub alias {
	my $self = &_self;
	if (ref($_[0]) eq 'HASH') { # perl style, merge hashes
		error 'alias: only first argument is used' if $#_;
		%{$self->{zoid}{aliases}} = ( %{$self->{zoid}{aliases}}, %{$_[0]} );
	}
	else { error q/alias: can't handle input data type: /.ref($_[0]) }
}

sub unalias {
	my $self = &_self;
	for (@_) {
		error "alias: $_: not found"
			unless delete $self->{zoid}{aliases}{$_};
	}
}

sub set {
	my $self = &_self;
	if (ref($_[0]) eq 'HASH') { # perl style, merge hashes
		error 'set: only first argument is used' if $#_;
		%{$self->{zoid}{settings}} = ( %{$self->{zoid}{settings}}, %{$_[0]} );
	}
	elsif (ref $_[0]) { error 'set: no support for data type'.ref($_[0]) }
	else {
		for (@_) { $self->{zoid}{settings}{$_}++ }
	}
}

sub setting {
	my $self = &_self;
	return $self->{zoid}{settings}{shift()} || undef;
}

1;

__END__

=head1 NAME

Zoidberg::Shell - a scripting interface to the Zoidberg shell

=head1 SYNOPSIS

        use Zoidberg::Shell;
	my $SHELL = Zoidberg::Shell->new();
       
	# Order parent shell to 'cd' to /usr
	# If you let your shell do 'cd' that is _NOT_ the same as doing 'chdir'
        $SHELL->shell(qw{cd /usr});
	
	# Let your parent shell execute a logic list with a pipeline
	$SHELL->shell([qw{ls -al}], [qw{grep ^d}], 'OR', [qw{echo some error happened}]);
	
	# Create an alias
	$SHELL->alias({'ls' => 'ls --color=auto'});
	
	# since we use Exporter::Tidy you can also do this:
	use Zoidberg::Shell _prefix => 'zoid_', qw/shell alias unalias/;
	zoid_alias({'perlfunc' => 'perldoc -Uf'});

=head1 DESCRIPTION

This module is intended to let perl scripts interface to the Zoidberg shell in an easy way.
The most important usage for this is to write 'source scripts' for the Zoidberg shell which can 
use and change the B<parent> shell environment like /.*sh/ source scripts 
do with /.*sh/ environments.

=head1 EXPORT

Only the subs C<AUTOLOAD> and C<shell> are exported by default.
C<AUTOLOAD> works more or less like the one from F<Shell.pm> by Larry Wall, but it 
includes zoid's builtin functions and commands (also it just prints output to stdout see TODO).

The other methods (except C<new>) can be exported on demand. 
Be aware of the fact that methods like C<alias> can mask "plugin defined builtins" 
with the same name, but with an other interface. If instead of exporting these methods
the L</AUTOLOAD> method is used, different behaviour can be expected.

=head1 METHODS

B<Be aware:> All commands are executed in the B<parent> shell environment, 
so if a command changes the environment these changes will change 
the environment of the parent shell, even when the script has long finished.

=over 4

=item C<new()>

Simple constructor.

=item C<shell($command, @_)>

If C<$command> is a built-in shell function (possibly defined by a plugin)
or a system binary, it will be run with arguments C<@_>.
The command won't be subject to alias expansion, arguments might be subject
to glob expansion.

If you just want the output of a system command use the L<system> method.

If you want to make I<sure> you get a built-in command use L<builtin>, you might
prevent some strange bugs.

=item C<shell([$command, @_], [..], 'AND', [..])>

Create a logic list and/or pipeline. Available tokens are 'AND', 'OR' and
'EOS' (End Of Statement, ';').

=item C<shell_string($string)>

Parse B<and> execute C<$string> like it was entered from the commandline.
You should realise that the parsing is dependent on grammars currently in use,
and also on things like aliases etc.

I<Using this form in a source script _will_ attract nasty bugs>

=item C<shell_tree([$context, @_], [..],'AND',[..])>

=item C<< shell_tree([ {context => $context}, @_ ]) >>

Like C<shell()> but lets lets you pass more meta data to the parse tree. 
This can be considered an "expert mode", see parser documentation/source elsewhere.

TODO - not yet implemented

=item C<set(..)>

Update settings in parent shell.

	# merge hash with current settings hash
	set( { noglob => 0 } );
	
	# set these bits to true
	set( qw/hide_private_method hide_hidden_files/);

=item C<alias(\%aliases)>

Merge C<%aliases> with current alias hash.

	alias( { ls => 'ls ---color=auto' } )

FIXME point to docs on aliases

=item C<unalias(@aliases)>

Delete all keys listed in C<@aliases> from the aliases table.

=item C<exec_error()>

Returns the error caused by the last executed command, or undef is all is well.

=item AUTOLOAD

All calls that get autoloaded are passed directly to the C<shell()> method.

=back

=head1 TODO

Not all routines that are documented are implemented yet

Currently stdout isn't captured if wantarray

An interface to create background jobs

An interface to get input

Merge this interface with Zoidberg::Fish ?

Can builtins support both perl data and switches ?

Test script

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Shell>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


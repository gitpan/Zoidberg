package Zoidberg::Shell;

use strict;
use vars qw/$AUTOLOAD/;
use Exporter;
use Carp;
use Zoidberg::Error;
use Zoidberg::FileRoutines qw/abs_path/;

our $VERSION = '0.3c';

our $DEBUG	= 0;
our @ISA	= qw/Exporter/;
our @EXPORT	= qw/AUTOLOAD/;
our @EXPORT_OK	= qw/
	AUTOLOAD sh builtin system cmd exec_error 
	alias unalias set setting
/;
our %EXPORT_TAGS = (
	all	=> \@EXPORT_OK,
	zoidrc	=> [qw/alias unalias set setting/],
);

# TODO unless ref($ENV{ZOIDREF}) start ipc

sub new { # undocumented for a reason
	my ($class, $ref) = @_;
	unless ($ref) {
		return unless ref($ENV{ZOIDREF}); # make use_ok test happy :((
		$ref = $ENV{ZOIDREF}->{zoid};
	}
	bless {zoid => $ref}, $class;
}

sub _self { (ref($_[0]) eq __PACKAGE__) ? shift : {zoid => $ENV{ZOIDREF}->{zoid}} }

# ################ #
# Parser interface #
# ################ #

sub AUTOLOAD {
	## Code inspired by Shell.pm ##
	my $cmd = (split/::/,$AUTOLOAD)[-1];
	return undef if $cmd eq 'DESTROY';
	carp "You shouldn't autoload OO methods for this object" if ref($_[0]) eq __PACKAGE__;
	print "debug: autoload got command: $cmd\n" if $DEBUG;
	sh($cmd, @_);
}

sub sh {
	my $self = &_self;
	my $tree = [];
	unless (ref $_[0]) {
		push @$tree, $self->{zoid}->parse_words(@_)
			|| error "zoid: $_[0]: command not found" ;
	}
	else { todo 'pipeline form' }
	for (@$tree) { $_->[0] = {context => $_->[0]} if ref($_) && ! ref($_->[0]) }
	# TODO capture output
	if (scalar(@$tree) == 1) { $self->{zoid}->do_job($tree, 'FG') }
	else { $self->{zoid}->do_list($tree) }
}

# Don't like the name - it masks CORE::system :((
#sub system {
#	my $self = &_self;
#	open CMD, '-|', $cmd, @_;
#	my @ret = (<CMD>);
#	close CMD;
#	$self->{zoid}{exec_error} = $?;
#	if (wantarray) { return map {chomp; $_} @ret }
#	else { return join('',@ret); }
#}
# reminder: error moet naar {zoid}{exec_error} so exec_error() will work transparently
# or a similar hack has to be made for this
# 
#=item C<system($command, @_)>
#
#Like C<sh(..)> but but enforces C<$command> to be a system binary.
#It is more efficient because it doesn't use the 
#normal Zoidparse structure.
#
#This routine returns the result of the executed command either as scalar, or
#-when in list context- as an array.
#
#No expansion of any kind will be done on the arguments.


sub builtin { todo }

sub cmd { todo }

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
		for (@_) { $self->{zoid}{settings}{$_} = 1 }
	}
}

sub setting {
	my $self = &_self;
	return $self->{zoid}{settings}{shift()} || undef;
}

1;

__END__

=head1 NAME

Zoidberg::Shell - an interface to the Zoidberg shell

=head1 SYNOPSIS

        use Zoidberg::Shell;
	my $SHELL = Zoidberg::Shell->new();
       
	# Order parent shell to 'cd' to /usr
	# If you let your shell do 'cd' that is _NOT_ the same as doing 'chdir'
        $SHELL->sh(qw{cd /usr});
	
	# Let your parent shell execute a logic list with a pipeline
	$SHELL->sh([qw{ls -al}], [qw{grep ^d}], 'OR', [qw{echo some error happened}]);
	
	# Create an alias
	$SHELL->alias({ 'ls' => 'ls --color=auto'});

=head1 DESCRIPTION

This module is intended to let perl scripts interface to the Zoidberg shell in an easy way.
The most important usage for this is to write 'source scripts' for the Zoidberg shell which can 
use and change the B<parent> shell environment like /.*sh/ source scripts 
do with /.*sh/ environments.

=head1 EXPORT

Only the C<AUTOLOAD> sub is exported by default.
C<AUTOLOAD> works more or less like the one from F<Shell.pm> by Larry Wall, but it 
includes zoid's builtin functions and commands (also it just prints output to stdout).

The other methods (except C<new>) can be exported on demand. 
Be aware of the fact that methods like C<alias> can mask "plugin defined builtins" 
with the same name, but with on other interface. If instead of exporting these methods
the L</AUTOLOAD> method is used, different behaviour can be expected.

=head1 METHODS

FIXME tell about OO and non-OO use

B<Be aware:> All commands are executed in the B<parent> shell environment, 
so if a command changes the environment these changes will change 
the environment of the parent shell, even when the script has long finished.

=over 4

=item C<new()>

Simple constructor.

=item C<sh($command, @_)>

If C<$command> is a built-in shell function (possibly defined by a plugin)
or a system binary, it will be run with arguments C<@_>.
The command won't be subject to alias expansion, arguments might be subject
to glob expansion.

If you just want the output of a system command use the L<system> method.

If you want to make I<sure> you get a built-in command use L<builtin>, you might
prevent some strange bugs.

=item C<sh([$command, @_], [..], 'AND', [..])>

Create a logic list and/or pipeline. Available tokens are 'AND', 'OR' and
'EOS' (End Of Statement, ';').

TODO - not yet implemented

=item C<builtin($command, @_)>

Like C<sh(..)>, but enforces C<$command> to be in the dispatch table for builtins.

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

=item C<cmd($string)>

Parse B<and> execute C<$string> like it was entered from the commandline.
You should realise that the parsing is dependent on grammars currently in use,
and also on things like aliases etc.

I<Using this form in a source script _will_ attract nasty bugs>

TODO - not yet implemented

=item C<cmd([$context, @_])>

Pass C<@_> to the plugin for this context.

TODO - not yet implemented

=item C<cmd([$context, @_], [..],'AND',[..])>

Create a logic list and/or pipeline.

TODO - not yet implemented

=item C<< cmd([ {context => $context}, @_ ]) >>

This form lets you pass more meta data to the parse tree. This can be considered
an "expert mode", see parser documentation/source elsewhere.

TODO - not yet implemented

=item C<exec_error()>

Returns the error caused by the last executed command, or undef is all is well.

=item AUTOLOAD

All calls that get autoloaded are passe directly to the C<sh()> method.

Using the AUTOLOADER in a object oriented way causes a warning, this is because
using it in this way can cause a lot of confusion since the autoloaded
commands will depend on the plugins currently in use and will not always
behave the same. Maybe it should even C<die> at such occasion, but then you 
wouldn't be able to pass a Zoidberg::Shell object to a command :S .

=back

=head1 TODO

Not all routines that are documented are implemented yet

Currently stdout isn't captured

An interface to create background jobs

An interface to get input

Merge this interface with Zoidberg::Fish ?

Test script

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Shell>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


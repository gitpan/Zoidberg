package Zoidberg::Shell;

our $VERSION = '0.42';

use strict;
use vars qw/$AUTOLOAD/;
use Zoidberg::Utils qw/:error :output abs_path/;
use Exporter::Tidy
	default	=> [qw/AUTOLOAD shell/],
	other	=> [qw/alias unalias set setting source/];
use UNIVERSAL qw/isa/;

sub new { return $ENV{ZOIDREF} }
# TODO unless ref($ENV{ZOIDREF}) start ipc

sub _self { (isa $_[0], __PACKAGE__) ? shift : $ENV{ZOIDREF} }

# ################ #
# Parser interface #
# ################ #

sub AUTOLOAD {
	## Code inspired by Shell.pm ##
	my $cmd = (split/::/, $AUTOLOAD)[-1];
	return undef if $cmd eq 'DESTROY';
	shift if ref($_[0]) eq __PACKAGE__;
	debug "Zoidberg::Shell::AUTOLOAD got $cmd";
	@_ = ([$cmd, @_]); # force words
	goto \&shell;
}

sub shell {
	my $self = &_self;
	my $pipe = ($_[0] =~ /^-\||\|-$/) ? shift : undef ;
	todo 'pipeline syntax' if $pipe;
	my $c = defined wantarray;
	my @re;
	if (grep {ref $_} @_) { @re = $self->shell_list({capture => $c}, @_) }
	elsif (@_ > 1) { @re = $self->shell_list({capture => $c}, \@_) }
	else { @re = $self->shell_string({capture => $c}, @_) }
	return ! $c ? undef : wantarray ? (map {chomp; $_} @re) : join('', @re);
}

sub system {
	# quick parser independent way of calling system commands
	# not exported to avoid conflict with perlfunc system
	my $self = &_self;
	open CMD, '|-', @_ or error "Could not open pipe to: $_[0]";
	my @re = (<CMD>);
	close CMD;
	return wantarray ? @re : join('', @re);
	# FIXME where does the error code of cmd go?
}

# ############# #
# Some builtins #
# ############# #

sub alias {
	my $self = &_self;
	if (ref($_[0]) eq 'HASH') { # perl style, merge hashes
		error 'alias: only first argument is used' if $#_;
		%{$self->{aliases}} = ( %{$self->{aliases}}, %{$_[0]} );
	}
	else { error q/alias: can't handle input data type: /.ref($_[0]) }
}

sub unalias {
	my $self = &_self;
	for (@_) {
		error "alias: $_: not found"
			unless delete $self->{aliases}{$_};
	}
}

sub set {
	my $self = &_self;
	if (ref($_[0]) eq 'HASH') { # perl style, merge hashes
		error 'set: only first argument is used' if $#_;
		%{$self->{settings}} = ( %{$self->{settings}}, %{$_[0]} );
	}
	elsif (ref $_[0]) { error 'set: no support for data type'.ref($_[0]) }
	else {  $self->{settings}{$_}++ for @_ }
}

sub setting {
	my $self = &_self;
	my $key = shift;
	return exists($$self{settings}{$key}) ? $$self{settings}{$key}  : undef;
}

sub source {
	my $self = &_self;
	local $ENV{ZOIDREF} = $self;
	for (@_) {
		my $file = abs_path($_);
		error "source: no such file: $file" unless -f $file;
		debug "going to source: $file";
		# FIXME more intelligent behaviour -- see bash man page
		eval q{package Main; do $file; die $@ if $@ };
		# FIXME wipe Main
		complain if $@;
	}
}

1;

__END__

=head1 NAME

Zoidberg::Shell - a scripting interface to the Zoidberg shell

=head1 SYNOPSIS

        use Zoidberg::Shell;
	my $shell = Zoidberg::Shell->new();
       
	# Order parent shell to 'cd' to /usr
	# If you let your shell do 'cd' that is _NOT_ the same as doing 'chdir'
        $shell->shell(qw{cd /usr});
	
	# Let your parent shell execute a logic list with a pipeline
	$shell->shell([qw{ls -al}], [qw{grep ^d}], 'OR', [qw{echo some error happened}]);
	
	# Create an alias
	$shell->alias({'ls' => 'ls --color=auto'});
	
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

All other methods except C<new> and C<system> can be exported on demand. 
Be aware of the fact that methods like C<alias> can mask "plugin defined builtins" 
with the same name, but with an other interface. This can be confusing but the idea is that
methods in this package have a scripting interface, while the like named builtins have
a commandline interface. The reason the C<system> can't be exported is because it would mask the 
perl function C<system>, also this method is only included so zoid's DispatchTable's can use it.

=head1 METHODS

B<Be aware:> All commands are executed in the B<parent> shell environment.

=over 4

=item C<new()>

Simple constructor. Doesn't actually construct a new object but just returns
the current L<Zoidberg> object, which in turn inherits from this package.

=item C<system($command, @_)>

Opens a pipe to a system command and returns it's output. Intended for when you want
to call a command B<without> using zoid's parser and job management. This method
has absolutely B<no> intelligence (no expansions, builtins,  etc.), you can only call
external commands with it.

=item C<shell($command, @_)>

If C<$command> is a built-in shell function (possibly defined by a plugin)
or a system binary, it will be run with arguments C<@_>.
The command won't be subject to alias expansion, arguments might be subject
to glob expansion. FIXME double check this

=item C<shell($string)>

Parse and execute C<$string> like it was entered from the commandline.
You should realise that the parsing is dependent on grammars currently in use,
and also on things like aliases etc.

=item C<shell([$command, @_], [..], 'AND', [..])>

Create a logic list and/or pipeline. Available tokens are 'AND', 'OR' and
'EOS' (End Of Statement, ';').

C<shell()> allows for other kinds of pseudo parse trees, these can be considered
as a kind of "expert mode". See L<zoiddevel(1)> for more details.
You might not want to use these without good reason.

=item C<set(..)>

Update settings in parent shell.

	# merge hash with current settings hash
	set( { noglob => 0 } );
	
	# set these bits to true
	set( qw/hide_private_method hide_hidden_files/ );

See L<zoiduser(1)> for a description of the several settings.

=item C<setting($setting)>

Returns the current value for a setting.

=item C<alias(\%aliases)>

Merge C<%aliases> with current alias hash.

	alias( { ls => 'ls ---color=auto' } )

=item C<unalias(@aliases)>

Delete all keys listed in C<@aliases> from the aliases table.

=item C<source($file)>

Run another perl script, possibly also interfacing with zoid.

FIXME more documentation on zoid's source scripts

=item C<AUTOLOAD>

All calls that get autoloaded are passed directly to the C<shell()> method.
This allows you to use nice syntax like :

	$shell->cd('..');

=back

=head1 TODO

Currently stdout isn't captured if wantarray in shell()

An interface to create background jobs

An interface to get input

Can builtins support both perl data and switches ?

Test script

More syntactic sugar :)

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Shell>, L<Zoidberg>, L<Zoidberg::Utils>,
L<http://zoidberg.sourceforge.net>

=cut


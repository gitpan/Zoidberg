package Zoidberg::Fish::Commands;

our $VERSION = '0.54';

use strict;
use AutoLoader 'AUTOLOAD';
use Cwd;
use Env qw/@CDPATH @DIRSTACK/;
use base 'Zoidberg::Fish';
use Zoidberg::Utils qw/:default abs_path/;

# FIXME what to do with commands that use block input ?
#  currently hacked with statements like join(' ', @_)

=head1 NAME

Zoidberg::Fish::Commands - Zoidberg plugin with builtin commands

=head1 SYNOPSIS

This module is a Zoidberg plugin, see Zoidberg::Fish for details.

=head1 DESCRIPTION

This object contains internal/built-in commands
for the Zoidberg shell.

=head2 EXPORT

None by default.

=cut

sub init { 
	$_[0]->{dir_hist} = [$ENV{PWD}];
	$_[0]->{_dir_hist_i} = 0;
}

=head1 COMMANDS

=over 4

=item cd I<dir>

Changes the current working directory to I<dir>.

=over 4

=item -b

Go one directory back in the directory history

=item -f

Go one directory forward in the directory history

=back

=cut

sub cd { # TODO [-L|-P] see man 1 bash
	my $self = shift;
	my ($dir, $browse_hack, $done);

	if ($_[0] =~ /^-[bf]$/) {
		$dir = $self->__get_dir_hist(@_);
		error q{History index out of range} unless defined $dir;
		$browse_hack++;
	}
	elsif ($_[0] eq '-') { 
		$dir = $ENV{OLDPWD};
		output $dir;
	}
	else { $dir = shift }

	unless ($dir) { $done = chdir() }
	else {
		# due to things like autofs we must try every possibility
		# instead of checking '-d'
		my @dirs = ($dir);
		push @dirs, map "$_/$dir", @CDPATH unless $dir =~ m#^\.{0,2}/#;

		for (@dirs) { last if $done = chdir abs_path($_) }
	}

	unless ($done) {
		error $dir.': Not a directory' unless -d $dir;
		error "Could not change to dir: $dir";
	}

	$self->__add_dir_hist unless $browse_hack;
}

1;

__END__

=item exec I<cmd>

Execute I<cmd>. This effectively ends the shell session,
process flow will B<NOT> return to the prompt.

=cut

sub exec { # FIXME not completely stable I'm afraid
	my $self = shift;
	$self->{parent}->{round_up} = 0;
	$self->{parent}->shell_string({fork_job => 0}, join(" ", @_));
	# the process should not make it to this line
	$self->{parent}->{round_up} = 1;
	$self->{parent}->exit;
}

=item eval I<cmd>

Eval I<cmd> like a shell command. Main use of this is to
run code stored in variables.

=cut

sub eval {
	my $self = shift;
	$self->parent->shell( join( ' ', @_) );
}

=item export I<var>=I<value>

Set the environment variable I<var> to I<value>.

=cut

sub export {
	my $self = shift;
	for (@_) {
		if ($_ =~ m/^(\w*)=(.*?)$/) { $ENV{$1} = $2 }
		else { error 'syntax error' }
	}
}

=item setenv I<var> I<value>

Like B<export>, but with a slightly different syntax.

=cut

sub setenv {
	my (undef, $var, $val) = @_;
	$ENV{$var} = $val;
}

=item unsetenv I<var>

Set I<var> to undefined.

=cut

sub unsetenv {
	my $self = shift;
	delete $ENV{$_} for @_;
}

=item set [+-][abCefnmnuvx]

=item set [+o|-o] I<option> I<value>

Set or unset a shell option. Although sometimes confusing
a '+' switch unsets the option, while the '-' switch sets it.

If no I<value> is given the value is set to 'true'.

Short options correspond to the following names:

	a  =>  allexport  *
	b  =>  notify
	C  =>  noclobber  *
	e  =>  errexit    *
	f  =>  noglob
	m  =>  monitor    *
	n  =>  noexec     *
	u  =>  nounset    *
	v  =>  verbose
	x  =>  xtrace     *
	*) Not yet supported by the rest of the shell

See L<zoiduser> for a description what these and other options do.

=cut

sub set {
	my $self = shift;
	# FIXME use some getopt
	# be aware '-' is set '+' is unset (!!??)
	unless (@_) { todo 'I should printout all shell vars' }

	my ($sw, $opt, $val);
	if ($_[0] =~ m/^([+-])(\w+)/) {
		shift;
		$sw = $1;
		my %args = (
			a => 'allexport',	b => 'notify',
			C => 'noclobber',	e => 'errexit',
			f => 'noglob',		m => 'monitor',
			n => 'noexec',		u => 'nounset',
			v => 'verbose',		x => 'xtrace',
		);
		# other posix options: ignoreeof, nolog & vi
		if ($2 eq 'o') { $opt = shift }
		elsif ($args{$2}) { $opt = $args{$2} }
		else { error "Switch $sw not (yet?) supported." }
	}
	else {
		$opt = shift;
		$sw = '-';
		if ($opt =~ m/^(.+?)=(.*)$/) { ($opt, $val) = ($1, $2) }
		elsif ($opt =~ m/^(.*)([+-]{2})$/) {
			$opt = $1;
			$sw = '+' if $2 eq '--'; # sh has evil logic
		}
	}
	
	$val = shift || 1 unless defined $val;
	error "$opt : this setting contains a reference" if ref $self->{settings}{$opt};

	my ($path, $ref) = ('/', $$self{parent}{settings});
	while ($opt =~ s#^/*(.+?)/##) {
		$path .= $1 . '/';
		if (! defined $$ref{$1}) { $$ref{$1} = {} }
		elsif (ref($ref) ne 'HASH') { error "$path : no such settings hash" }
		$ref = $$ref{$1};
	}
	debug "setting: $opt, value: $val, path: $path";

	if ($sw eq '+') { delete $$ref{$opt} }
	else { $$ref{$opt} = $val }
}

=item source I<file>

Run the B<perl> script I<file>. This script is B<NOT> the same
as the commandline syntax. Try using L<Zoidberg::Shell> in these
scripts.

=cut

sub source {
	my $self = shift;
	# FIXME more intelligent behaviour -- see bash man page
	$self->{parent}->source(@_);
}

=item alias

=item alias I<name>

=item alias I<name>=I<command>

=item alias I<name> I<command>

Make I<name> an alias to I<command>. Aliases work like macros
in the shell, this means they are substituted before the commnd
code is interpreted and can contain complex statements.

In zoid you also can use positional parameters (C<$_[0]>, C<$_[1]>
etc.) and C<@_>, which will be replaced with the arguments to the alias.

Without I<command> shows the alias defined for I<name> if any;
without arguments lists all aliases that are currently defined.

=cut

sub alias {
	my $self = shift;
	unless (@_) {
		output [
			map {
				my $al = $$self{parent}{aliases}{$_};
				$al =~ s/(\\)|'/$1 ? '\\\\' : '\\\''/eg;
				"alias $_='$al'",
			} keys %{$$self{parent}{aliases}}
		];
	}
	elsif ($_[0] !~ /^(\w+)=/) {
		my $cmd = shift;
		if (@_) { # tcsh alias format
			$self->{parent}{aliases}{$cmd} = join ' ', @_;
		}
		else {
			error "$cmd: no such alias"
				unless exists $$self{parent}{aliases}{$cmd};
			my $al = $$self{parent}{aliases}{$cmd};
			$al =~ s/(\\)|'/$1 ? '\\\\' : '\\\''/eg;
			output "alias $cmd='$al'";
		}	
	}
	else {
		for (@_) {
			/^(\w+)=(.*?)$/;
			$self->{parent}{aliases}{$1} = $2;
		}
	}
}

=item unalias I<name>

Remove an alias definition.

=cut

sub unalias {
	my $self = shift;
	if ($_[0] eq '-a') { %{$self->{parent}{aliases}} = () }
	else {
		for (@_) {
			error "alias: $_: not found" unless exists $self->{parent}{aliases}{$_};
			delete $self->{parent}{aliases}{$_};
		}
	}
}

=item read [-r] I<var1> I<var2 ..>

Read a line from STDIN, split the line in words 
and assign the words to the named enironment variables.
Remaining words are stored in the last variable.

Unless '-r' is specified the backslash is treated as
an escape char and is it possible to escape the newline char.

=cut

sub read {
	my $self = shift;
	my $esc = 1;
	$esc = 0 and shift if $_[0] eq '-r';

	my $string = '';
	while (<STDIN>) {
		if ($esc) {
			my $more = 0;
			$_ =~ s/(\\\\)|\\(.)|\\$/
				if ($1) { '\\' }
				if (length $2) { $2 }
				else { $more++; '' }
			/eg;
			$string .= $_;
			last unless $more;
		}
		else {
			$string = $_;
			last;
		}
	}
	return unless @_;

	my @words = $$self{parent}{stringparser}->split('word_gram', $string);
	debug "read words: ", \@words;
	if (@words > @_) {
		@words = @words[0 .. $#_ - 1];
		my $re = join '\s*', @words;
		$string =~ s/^\s*$re\s*//;
		push @words, $string;
	}

	$ENV{$_} = shift @words || '' for @_;
}

=item command

TODO

=cut

sub command { todo }

=item newgrp

TODO

=cut

sub newgrp { todo }

=item umask

TODO

=cut

sub umask { todo }

=item false

A command that always returns an error without doing anything.

=cut

sub false { error {silent => 1}, 'the "false" builtin' }

=item true

A command that never fails and does absolutely nothing.

=cut

sub true { 1 }

# ######## #
# Dir Hist #
# ######## #

sub __add_dir_hist {
	my $self = shift;
	my $dir = shift || $ENV{PWD};

	return if $dir eq $self->{dir_hist}[0];

	unshift @{$self->{dir_hist}}, $dir;
	$self->{_dir_hist_i} = 0;

	my $max = $self->{config}{max_dir_hist} || 5;
	pop @{$self->{dir_hist}} if $#{$self->{dir_hist}} > $max ;
}

sub __get_dir_hist {
	my $self = shift;

	my ($sign, $num);
	if (scalar(@_) > 1) { ($sign, $num) = @_ }
	elsif (@_) { ($sign, $num) = (shift(@_), 1) }
	else { $sign = '-' }

	if ($sign eq '-') { return $ENV{OLDPWD} }
	elsif ($sign eq '-f') { $self->{_dir_hist_i} -= $num }
	elsif ($sign eq '-b') { $self->{_dir_hist_i} += $num }
	else { return undef }

	return undef if $num < 0 || $num > $#{$self->{dir_hist}};
	return $self->{dir_hist}[$num];
}

# ######### #
# Dir stack #
# ######### # 

=item dirs

Output the current dir stack.

TODO some options

=cut

sub dirs { print join(' ', reverse @DIRSTACK) || $ENV{PWD}, "\n" }
# FIXME some options - see man bash

=item popd I<dir>

Pops a directory from the dir stack and B<cd>s to that directory.

TODO some options

=cut

sub popd { # FIXME some options - see man bash
	my $self = shift;
	error 'popd: No other dir on stack' unless $#DIRSTACK;
	pop @DIRSTACK;
	my $dir = $#DIRSTACK ? $DIRSTACK[-1] : pop(@DIRSTACK);
	$self->cd($dir);
}

=item pushd I<dir>

Push I<dir> on the dir stack.

TODO some options

=cut

sub pushd { # FIXME some options - see man bash
	my ($self, $dir) = (@_);
	my $pwd = $ENV{PWD};
	$dir ||= $ENV{PWD};
	$self->cd($dir);
	@DIRSTACK = ($pwd) unless scalar @DIRSTACK;
	push @DIRSTACK, $dir;
}

##################

=item pwd

Prints the current PWD.

=cut

sub pwd {
	my $self = shift;
	output $ENV{PWD};
}


sub _delete_object { # FIXME some kind of 'force' option to delte config, so autoload won't happen
	my ($self, $zoidname) = @_;
	error 'Usage: $command $object_name' unless $zoidname;
	error "No such object: $zoidname"
		unless exists $self->{parent}{objects}{$zoidname};
	delete $self->{parent}{objects}{$zoidname};
}

sub _load_object {
	my ($self, $name, $class) = (shift, shift, shift);
	error 'Usage: $command $object_name $class_name' unless $name && $class;
	$self->{parent}{objects}{$name} = { 
		module       => $class,
		init_args    => \@_,
		load_on_init => 1 ,
	};
}

sub _hide {
	my $self = shift;
	my $ding = shift || $self->{parent}{topic};
	if ($ding =~ m/^\{(\w*)\}$/) {
		@{$self->{settings}{clothes}{keys}} = grep {$_ ne $1} @{$self->{settings}{clothes}{keys}};
	}
	elsif ($ding =~ m/^\w*$/) {
		@{$self->{settings}{clothes}{subs}} = grep {$_ ne $ding} @{$self->{settings}{clothes}{subs}};
	}
}

sub _unhide {
	my $self = shift;
	my $ding = shift || $self->{parent}{topic};
	$self->{parent}->{topic} = '->'.$ding;
	if ($ding =~ m/^\{(\w*)\}$/) { push @{$self->{settings}{clothes}{keys}}, $1; }
	elsif (($ding =~ m/^\w*$/)&& $self->parent->can($ding) ) {
		push @{$self->{settings}{clothes}{subs}}, $ding;
	}
	else { error 'Dunno such a thing' }
}

# ############ #
# Job routines #
# ############ #

=item jobs

List current jobs.

=cut

sub jobs {
	my $self = shift;
	my $j = @_ ? \@_ : $$self{parent}->{jobs};
	output $_->status_string for sort {$$a{id} <=> $$b{id}} @$j;
}

=item bg I<job_spec>

Run the job corresponding to I<jobspec> as an asynchronous background process.

Without argument uses the "current" job.

=cut

sub bg {
	my ($self, $id) = @_;
	my $j = $$self{parent}->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting bg: $$j{id} == $j";
	$j->put_bg;
}

=item fg I<job_spec>

Run the job corresponding to I<jobspec> as a foreground process.

Without argument uses the "current" job.

=cut

sub fg {
	my ($self, $id) = @_;
	my $j = $$self{parent}->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting fg: $$j{id} == $j";
	$j->put_fg;
}

=item wait

TODO

=cut

sub wait { todo }

=item kill -l

=item kill [-s I<sigspec>|-n I<signum>|I<-sigspec>] [I<pid>|I<job__pec>]

Sends a signal to a process or a process group.
By default the "TERM" signal is used.

The '-l' option list all possible signals.

=cut

# from bash-2.05/builtins/kill.def:
# kill [-s sigspec | -n signum | -sigspec] [pid | job]... or kill -l [sigspec]
# Send the processes named by PID (or JOB) the signal SIGSPEC.  If
# SIGSPEC is not present, then SIGTERM is assumed.  An argument of `-l'
# lists the signal names; if arguments follow `-l' they are assumed to
# be signal numbers for which names should be listed.  Kill is a shell
# builtin for two reasons: it allows job IDs to be used instead of
# process IDs, and, if you have reached the limit on processes that
# you can create, you don't have to start a process to kill another one.

# Notice that POSIX specifies another list format then the one bash uses

sub kill {
	my $self = shift;
	error "usage:  kill [-s sigspec | -n signum | -sigspec] [pid | job]... or kill -l [sigspec]"
		unless defined $_[0];
	if ($_[0] eq '-l') { # list sigs
		shift;
		my %sh = %{ $$self{parent}{_sighash} };
		my @k = @_ ? (grep exists $sh{$_}, @_) : (keys %sh);
		output [ map {sprintf '%2i) %s', $_, $sh{$_}} sort {$a <=> $b} @k ];
		return;
	}

	my $sig = '15'; # sigterm, the default
	if ($_[0] =~ /^--?(\w+)/) {
		if ( defined (my $s = $$self{parent}->sig_by_spec($1)) ) {
			$sig = $s;
			shift;
		}
	}
	elsif ($_[0] eq '-s') {
		shift;
		$sig = $$self{parent}->sig_by_spec(shift);
	}

	for (@_) {
		if (/^\%/) {
			my $j = $$self{parent}->job_by_spec($_);
			CORE::kill($sig, -$j->{pgid});
		}
		else { CORE::kill($sig, $_) }
	}
}

=item disown

TODO

=cut

sub disown { # dissociate job ... remove from @jobs, nohup
	todo 'see bash manpage for implementaion details';

	# is disowning the same as deamonizing the process ?
	# if it is, see man perlipc for example code

	# does this suggest we could also have a 'own' to hijack processes ?
	# all your pty are belong:0
}

=back

=head2 Job specs

TODO tell bout job specs

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>
R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Fish>, L<http://zoidberg.sourceforge.net>

=cut

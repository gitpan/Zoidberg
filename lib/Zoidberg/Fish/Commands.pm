package Zoidberg::Fish::Commands;

our $VERSION = '0.91';

use strict;
use AutoLoader 'AUTOLOAD';
use Cwd;
use Env qw/@CDPATH @DIRSTACK/;
use base 'Zoidberg::Fish';
use Zoidberg::Utils qw/:default path getopt usage path2hashref/;

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
	$_[0]{dir_hist} = [$ENV{PWD}]; # FIXME try to read log first
	$_[0]{_dir_hist_i} = 0;
}

=head1 COMMANDS

=over 4

=item cd I<dir>

=item cd -

=item cd [I<+->]I<number>

Changes the current working directory to I<dir>.
When used with a single dash changes to OLDPWD.

This command uses the environment variable 'CDPATH'. It serves as
a search path when the directory you want to change to isn't found
in the current directory.

This command also uses a directory history.
The '-number' and '+number' switches are used to change directory
back and forward in this history. Note that 'cd -' and 'cd -1'
have a different effect.

=cut

sub cd { # TODO [-L|-P] see man 1 bash # FIXME simplify be putting fully specified pwd in history .. and log it
	my $self = shift;
	my ($dir, $done, $verbose);
	if (@_ == 1 and $_[0] eq '-') { # cd -
		$dir = $ENV{OLDPWD};
		$verbose++;
	}
	else {
		my ($opts, $args) = getopt 'list,-l verbose,-v +* -* @', @_;
		error 'usage: cd [-l,--list|-v,--verbose|-idx|+idx] [dir]'
			if %$opts > 2 or @$args > 1 or %$opts && @$args;
		unless (%$opts) { # 'normal' cd
			$dir = $$args[0];
			unless ($dir eq $$self{dir_hist}[0]) {
				unshift @{$$self{dir_hist}}, $dir;
				$$self{_dir_hist_i} = 0;
				splice @{$$self{dir_hist}}, $$self{config}{max_dir_hist}
					if defined $$self{config}{max_dir_hist};
			}
		}
		elsif ($$opts{list}) { # list dirhist
			output [reverse @{$$self{dir_hist}}];
			return;
		}
		elsif ($$opts{verbose}) { $verbose++ }
		else { # cd back/forward in history
			error 'usage: cd [-l,--list|-idx|+idx] [dir]'
				unless $$opts{_opts}[0] =~ /^[+-]\d+$/;
			my $idx = $$self{_dir_hist_i} - $$opts{_opts}[0];
			error qq{No $_[0] in dir history}
				unless $idx >= 0 and $idx <= $#{$$self{dir_hist}};
			$$self{_dir_hist_i} = $idx;
			$dir = $$self{dir_hist}[ $$self{_dir_hist_i} ];
			$verbose++;
		}
	}

	if ($dir) {
		# due to things like autofs we must try every possibility
		# instead of checking '-d'
		$done = chdir path($dir);
		if    ($done)                { message $dir if $verbose }
		elsif ($dir !~ m#^\.{0,2}/#) {
			for (@CDPATH) {
				next unless $done = chdir path("$_/$dir");
				message "$_/$dir" if $verbose;
				last;
			}
		}
	}
	else {
		message $ENV{HOME} if $verbose;
		$done = chdir($ENV{HOME});
	}

	unless ($done) {
		error $dir.': Not a directory' unless -d $dir;
		error "Could not change to dir: $dir";
	}
}

1;

__END__

=item exec I<cmd>

Execute I<cmd>. This effectively ends the shell session,
process flow will B<NOT> return to the prompt.

=cut

sub exec { # FIXME not completely stable I'm afraid
	my $self = shift;
	$self->{shell}->{round_up} = 0;
	$self->{shell}->shell_string({fork_job => 0}, join(" ", @_));
	# the process should not make it to this line
	$self->{shell}->{round_up} = 1;
	$self->{shell}->exit;
}

=item eval I<cmd>

Eval I<cmd> like a shell command. Main use of this is to
run code stored in variables.

=cut

sub eval {
	my $self = shift;
	$$self{shell}->shell(@_);
}

=item export I<var>=I<value>

Set the environment variable I<var> to I<value>.

TODO explain how export moved varraibles between the perl namespace and the environment

=cut

sub export { # TODO if arg == 1 and not hash then export var from zoid::eval to env :D
	my $self = shift;
	my ($opt, $args, $vals) = getopt 'unexport,n print,p *', @_;
	my $class = $$self{shell}{settings}{perl}{namespace};
	no strict 'refs';
	if ($$opt{unexport}) {
		for (@$args) {
			s/^([\$\@]?)//;
			next unless exists $ENV{$_};
			if ($1 eq '@') { @{$class.'::'.$_} = split ':', delete $ENV{$_} }
			else { ${$class.'::'.$_} = delete $ENV{$_} }
		}
	}
	elsif ($$opt{print}) {
		output [ map {
			my $val = $ENV{$_};
			$val =~ s/'/\\'/g;
			"export $_='$val'";
		} sort keys %ENV ];
	}
	else { # really export
		for (@$args) {
			s/^([\$\@]?)//;
			next if defined $ENV{$_};
			if ($1 eq '@') { # arrays
				my @env  = defined($$vals{$_})               ? (@{$$vals{$_}})     :
					   defined(*{$class.'::'.$_}{ARRAY}) ? (@{$class.'::'.$_}) : ();
				$ENV{$_} = join ':', @env;
			}
			else { # scalars
				$ENV{$_} = defined($$vals{$_})        ? $$vals{$_}        :
		        		   defined(${$class.'::'.$_}) ? ${$class.'::'.$_} : ''
			}
		}
	}
}

=item setenv I<var> I<value>

Like B<export>, but with a slightly different syntax.

=cut

sub setenv {
	shift;
	my $var = shift;
	$ENV{$var} = join ' ', @_;
}

=item unsetenv I<var>

Set I<var> to undefined.

=cut

sub unsetenv {
	my $self = shift;
	delete $ENV{$_} for @_;
}

=item set [+-][abCefnmnuvx]

=item set [+o|-o] I<option>

Set or unset a shell option. Although sometimes confusing
a '+' switch unsets the option, while the '-' switch sets it.

Short options correspond to the following names:

	a  =>  allexport  *
	b  =>  notify
	C  =>  noclobber
	e  =>  errexit    *
	f  =>  noglob
	m  =>  monitor    *
	n  =>  noexec     *
	u  =>  nounset    *
	v  =>  verbose
	x  =>  xtrace     *
	*) Not yet supported by the rest of the shell

See L<zoiduser> for a description what these and other options do.

FIXME takes also hash arguments

=cut

sub set {
	my $self = shift;
	unless (@_) { error 'should print out all shell vars, but we don\'t have these' }
	my ($opts, $keys, $vals) = getopt
	'allexport,a	notify,b	noclobber,C	errexit,e
	noglob,f	monitor,m	noexec,n	nounset,u
	verbose,v	xtrace,x	-o@ +o@  	*', @_;
	# other posix options: ignoreeof, nolog & vi - bash knows a bit more

	my %settings;
	if (%$opts) {
		$settings{$_} = $$opts{$_}
			for grep {$_ !~ /^[+-]/} @{$$opts{_opts}};
		if ($$opts{'-o'}) { $settings{$_} = 1 for @{$$opts{'-o'}} }
		if ($$opts{'+o'}) { $settings{$_} = 0 for @{$$opts{'+o'}} }
	}

	for (@$keys) { $settings{$_} = defined($$vals{$_}) ? delete($$vals{$_}) : 1 }

	for my $opt (keys %settings) {
		if ($opt =~ m#/#) {
			my ($hash, $key, $path) = path2hashref($$self{shell}{settings}, $opt);
			error "$path: no such hash in settings" unless $hash;
			$$hash{$key} = $settings{$opt};
		}
		else { $$self{shell}{settings}{$opt} = $settings{$opt} }
	}
}

=item source I<file>

Run the B<perl> script I<file>. This script is B<NOT> the same
as the commandline syntax. Try using L<Zoidberg::Shell> in these
scripts.

=cut

sub source {
	my $self = shift;
	# FIXME more intelligent behaviour -- see bash man page
	$self->{shell}->source(@_);
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
	unless (@_) { # FIXME doesn't handle namespaces / sub hashes
		my $ref = $$self{shell}{aliases};
		output [
			map {
				my $al = $$ref{$_};
				$al =~ s/(\\)|'/$1 ? '\\\\' : '\\\''/eg;
				"alias $_='$al'",
			} grep {! ref $$ref{$_}} keys %$ref
		];
		return;
	}
	elsif (@_ == 1 and ! ref($_[0]) and $_[0] !~ /^-|=/) {
		my $cmd = shift;
		my $alias;
		if ($cmd =~ m#/#) {
			my ($hash, $key, $path) = path2hashref($$self{shell}{aliases}, $cmd);
			error "$path: no such hash in aliases" unless $hash;
			$alias = $$hash{$key};
		}
		elsif (exists $$self{shell}{aliases}{$cmd}) {
			$alias = $$self{shell}{aliases}{$cmd};
	       	}
		else { error $cmd.': no such alias' }
		$alias =~ s/(\\)|'/$1 ? '\\\\' : '\\\''/eg;
		output "alias $cmd='$alias'";
		return;
	}
	
	my (undef, $keys, $val) = getopt '*', @_;
	return unless @$keys;
	my $aliases;
	if (@$keys == (keys %$val)) { $aliases = $val } # bash style
	elsif (! (keys %$val)) { $aliases = {$$keys[0] => join ' ', splice @$keys, 1} }# tcsh style
	else { error 'syntax error' } # mixed style !?

	for my $cmd (keys %$aliases) {
		if ($cmd =~ m#/#) {
			my ($hash, $key, $path) = path2hashref($$self{shell}{aliases}, $cmd);
			error "$path: no such hash in aliases" unless $hash;
			$$hash{$key} = $$aliases{$cmd};
		}
		else { $$self{shell}{aliases}{$cmd} = $$aliases{$cmd} }
	}
}

=item unalias I<name>

Remove an alias definition.

=cut

sub unalias {
	my $self = shift;
	my ($opts, $args) = getopt 'all,a @', @_;
	if ($$opts{all}) { %{$self->{shell}{aliases}} = () }
	else {
		for (@$args) {
			error "alias: $_: not found" unless exists $self->{shell}{aliases}{$_};
			delete $self->{shell}{aliases}{$_};
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
	my ($opts, $args) = getopt 'raw,r @';

	my $string = '';
	while (<STDIN>) {
		unless ($$opts{raw}) {
			my $more = 0;
			$_ =~ s/(\\\\)|\\(.)|\\$/
				if ($1) { '\\' }
				elsif (length $2) { $2 }
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
	return unless @$args;

	my @words = $$self{shell}{stringparser}->split('word_gram', $string);
	debug "read words: ", \@words;
	if (@words > @$args) {
		@words = @words[0 .. $#$args - 1];
		my $pre = join '\s*', @words;
		$string =~ s/^\s*$pre\s*//;
		push @words, $string;
	}

	$ENV{$_} = shift @words || '' for @$args;
}

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

# ######### #
# Dir stack #
# ######### # 

=item dirs

Output the current dir stack.

TODO some options

Note that the dir stack is ont related to the dir history.
It was only implemented because historic implementations have it.

=cut

sub dirs { output @DIRSTACK ? [reverse @DIRSTACK] : $ENV{PWD} }
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

=item symbols [-a|--all] [CLASS]

Output a listing of symbols in the specified class.
Class defaults to the current perl namespace, by default
C<Zoidberg::Eval>.

All symbols are prefixed by their sigil ('$', '@', '%', '&'
or '*') where '*' is used for filehandles.

By default sub classes (hashes containing '::')
and special symbols (symbols without letters in their name)
are hidden. Use the --all switch to see these.

=cut

sub symbols {
	no strict 'refs';
	my $self = shift;
	my ($opts, $class) = getopt 'all,a @', @_;
	error 'usage: symbols [-a|--all] [CLASS]' if @$class > 1;
	$class = shift(@$class)
       		|| $$self{shell}{settings}{perl}{namespace} || 'Zoidberg::Eval';
	my @sym;
	for (keys %{$class.'::'}) {
		unless ($$opts{all}) {
			next if /::/;
			next unless /[a-z]/i;
		}
		push @sym, '$'.$_ if defined ${$class.'::'.$_};
		push @sym, '@'.$_ if *{$class.'::'.$_}{ARRAY};
		push @sym, '%'.$_ if *{$class.'::'.$_}{HASH};
		push @sym, '&'.$_ if *{$class.'::'.$_}{CODE};
		push @sym, '*'.$_ if *{$class.'::'.$_}{IO};
	}
	output [sort @sym];
}

=item help [TOPIC|COMMAND]

Prints out a help text.

=cut

sub help { # TODO topics from man1 pod files ??
	my $self = shift;
	unless (@_) {
		output << 'EOH';
Help topics:
  about
  command

see also man zoiduser
EOH
		return;
	}

	my $topic = shift;
	if ($topic eq 'about') { output "$Zoidberg::LONG_VERSION\n" }
	elsif ($topic eq 'command') {
		error 'usage: help command COMMAND' unless scalar @_;
		$self->help_command(@_)
	}
	else { $self->help_command($topic, @_) }
}

sub help_command {
	my ($self, @cmd) = @_;
	my @info = $self->type_command(@cmd);
	if ($info[0] eq 'alias') { output "'$cmd[0]' is an alias\n  > $info[1]" }
	elsif ($info[0] eq 'builtin') {
		output "'$cmd[0]' is a builtin command,";
		if (@info == 1) {
			output "but there is no information available about it.";
		}
		else {
			output "it belongs to the $info[1] plugin.";
			if (@info == 3) { output "\n", usage($cmd[0], $info[2]) }
			else { output "\nNo other help available" }
		}
	}
	elsif ($info[0] eq 'system') {
		output "'$cmd[0]' seems to be a system command, try\n  > man $cmd[0]";
	}
	elsif ($info[0] eq 'PERL') {
		output "'$cmd[0]' seems to be a perl command, try\n  > perldoc -f $cmd[0]";
	}
	else { todo "Help functionality for context: $info[1]" }
}

=item which [-a|--all|-m|--module] ITEM

Finds ITEM in PATH or INC if the -m or --module option was used.
If the -a or --all option is used all it doesn't stop after the first match.

TODO it should identify aliases

TODO what should happen with contexts other then CMD ?

=cut

sub which {
	my $self = shift;
	my ($opt, $cmd) = getopt 'module,m all,a @', @_;
	my @info = $self->type_command(@$cmd);
	$cmd = shift @$cmd;
	my @dirs;

	if ($$opt{module}) {
		$cmd =~ s#::#/#g;
		$cmd .= '.pm' unless $cmd =~ /\.\w+$/;
		@dirs = @INC;
	}
	else {
		error "$cmd is a, or belongs to a $info[0]"
			unless $info[0] eq 'system';
		# TODO aliases
		@dirs = split ':', $ENV{PATH};
	}

	my @matches;
	for (@dirs) {
		next unless -e "$_/$cmd";
		push @matches, "$_/$cmd";
		last unless $$opt{all};
	}
	if (@matches) { output [@matches] }
	else { error "no $cmd in PATH" }
	return;
}

sub type_command {
	my ($self, @cmd) = @_;
	
	if (
		exists $$self{shell}{aliases}{$cmd[0]}
		and $$self{shell}{aliases}{$cmd[0]} !~ /^$cmd[0]\b/
	) {
		my $alias = $$self{shell}{aliases}{$cmd[0]};
		$alias =~ s/'/\\'/g;
		return 'alias', "alias $cmd[0]='$alias'";
	}

	my $block = $$self{shell}->parse_block({pretend => 1}, [@cmd]);
	my $context = uc $$block[0]{context};
	if (!$context or $context eq 'CMD') {
		return 'system' unless exists $$self{shell}{commands}{$cmd[0]};
		my $tag = Zoidberg::DispatchTable::tag($$self{shell}{commands}, $cmd[0]);
		return 'builtin' unless $tag;
		my $file = tied( %{$$self{shell}{objects}} )->[1]{$tag}{module};
		return 'builtin', $tag, $file;
	}
	else { return $context }
}

# ############ #
# Job routines #
# ############ #

=item jobs

List current jobs.

=cut

sub jobs {
	my $self = shift;
	my $j = @_ ? \@_ : $$self{shell}->{jobs};
	output $_->status_string() for sort {$$a{id} <=> $$b{id}} @$j;
}

=item bg I<job_spec>

Run the job corresponding to I<jobspec> as an asynchronous background process.

Without argument uses the "current" job.

=cut

sub bg {
	my ($self, $id) = @_;
	my $j = $$self{shell}->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting bg: $$j{id} == $j";
	$j->bg;
}

=item fg I<job_spec>

Run the job corresponding to I<jobspec> as a foreground process.

Without argument uses the "current" job.

=cut

sub fg {
	my ($self, $id) = @_;
	my $j = $$self{shell}->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting fg: $$j{id} == $j";
	$j->fg;
}

=item wait

TODO

=cut

sub wait { todo }

=item kill -l

=item kill [-w | -s I<sigspec>|-n I<signum>|I<-sigspec>] [I<pid>|I<job__pec>]

Sends a signal to a process or a process group.
By default the "TERM" signal is used.

The '-l' option list all possible signals.

The -w or --wipe option is zoidberg specific. It not only kills the job, but also
wipes the list that would be executed after the job ends.

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
	my ($opts, $args) = getopt 'wipe,-w list,-l sigspec,-s signum,-n -* @', @_;
	error "usage:  kill [-w] [-s sigspec | -n signum | -sigspec] [pid | job]... or kill -l [sigspecs]"
		unless %$opts || @$args;
	if ($$opts{list}) { # list sigs
		error 'too many options' if @{$$opts{_opts}} > 1;
		my %sh = %{ $$self{shell}{_sighash} };
		my @k = @$args ? (grep exists $sh{$_}, @$args) : (keys %sh);
		output [ map {sprintf '%2i) %s', $_, $sh{$_}} sort {$a <=> $b} @k ];
		return;
	}

	my $sig = $$opts{signum} || '15'; # sigterm, the default
	if ($$opts{_opts}) {
		for ($$opts{signum}, grep s/^-//, @$args) {
			next unless $_;
			my $sig = $$self{shell}->sig_by_spec($_);
			error $_.': no such signal' unless defined $sig;
		}
	}

	for (@$args) {
		if (/^\%/) {
			my $j = $$self{shell}->job_by_spec($_)
				or error "$_: no such job";
			$j->kill($sig, $$opts{wipe});
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

L<Zoidberg>, L<Zoidberg::Fish>

=cut

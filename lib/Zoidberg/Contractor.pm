package Zoidberg::Contractor;

our $VERSION = '0.53';

use strict;
use POSIX ();
use Config;
use Zoidberg::Utils;
use Zoidberg::Eval;

sub new { # stub, to be overloaded
	my $class = shift;
	shell_init(bless {@_}, $class);
}

# Job control code adapted from example code 
# in the glibc manual <http://www.gnu.org/software/libc/manual>
# also some snippets from this manual include as comment blocks

# A subshell that runs non-interactively cannot and should not support job control.

sub shell_init {
	my $self = shift;
	bug 'Contractor can\'t live without a shell' unless $$self{shell};

	## add some commands - FIXME this doesn't belong here, breaks interface
	$self->{shell}{commands}{$_}   = $_  for qw/fg bg kill jobs/;

	## jobs stuff
	$self->{jobs} = [];
	$self->{_sighash} = {};
	$self->{terminal} = fileno(STDIN);

	my @sno = split /[, ]/, $Config{sig_num};
	my @sna = split /[, ]/, $Config{sig_name};
	$self->{_sighash}{$sno[$_]} = $sna[$_] for (0..$#sno);

	if ($self->{shell}{settings}{interactive}) {
		# Loop check until we are in the foreground.
		while (POSIX::tcgetpgrp($self->{terminal}) != ($self->{pgid} = getpgrp)) {
			kill (21, -$self->{pgid}); # SIGTTIN, stopping ourselfs 
			# not using constants to prevent namespace pollution
		}
		# ignore interactive and job control signals
		$SIG{$_} = 'IGNORE' for qw/INT QUIT TSTP TTIN TTOU/;

		# And get terminal control
		POSIX::tcsetpgrp($self->{terminal}, $self->{pgid});
		$self->{tmodes} = POSIX::Termios->new;
		$self->{tmodes}->getattr;
	}
	else { $self->{pgid} = getpgrp }

	return $self;
}

sub round_up { $_->round_up() for @{$_[0]->{jobs}} }

sub shell_list {
	my ($self, @list) = grep {defined $_} @_;

	my $save_fg_job = $$self{shell}{fg_job}; # could be undef

	my $meta = (ref($list[0]) eq 'HASH') ? shift(@list) : {} ;
	return unless @list;
	my $j = Zoidberg::Job->new(%$meta, boss => $self, tree => \@list) or return;
	my @re = $j->exec();

	$$self{shell}{fg_job} = $save_fg_job;

	return @re;
}


sub reap_jobs {
	my $self = shift;
	return unless  @{$self->{jobs}};
	my (@completed, @running);
	debug 'reaping jobs';
	for ( @{$self->{jobs}} ) {
		$_->update_status;
		if ($_->completed) {
			if (@{$$_{tree}}) { $self->reinc_job($_) } # reincarnate it
			else { push @completed, $_ }
		}
		else { push @running, $_ }
	}
	$self->{jobs} = \@running;
	debug 'body count: '.scalar(@completed);
	if ($$self{shell}{settings}{interactive}) {
		++$$_{completed} and message $_->status_string
			for sort {$$a{id} <=> $$b{id}} grep {! $$_{no_notify}} @completed;
	}

	# reinc completed if tree
	# FIXME FIXME heartbeat
}

sub reinc_job { # reincarnate
	my ($self, $job) = @_;
	my $op = ref( $$job{tree}[0] ) ? 'EOS' : shift @{ $$job{tree} } ;

	debug "job \%$$job{id} reincarnates, op $op";
	# mind that logic grouping for AND and OR isn't the same, OR is stronger
	while ( $$self{shell}{error} ? ( $op eq 'AND' ) : ( $op eq 'OR' ) ) { # skip
		my $i = 0;
		while ( ref $$job{tree}[0] or $$job{tree}[0] eq 'AND' ) {
			shift @{ $$job{tree} };
			$i++;
		}
		debug "error => $i blocks skipped";
		$op = shift @{ $$job{tree} };
	}

	return unless @{ $$job{tree} };

	
	my @b = @{ $$job{tree} };
	$$job{tree} = [];
	debug @b. ' blocks left';
	$self->shell_list({ bg => $$job{bg}, id => $$job{id} }, @b); # should capture be inherited ?
}

# ############ #
# Job routines #
# ############ #

sub jobs {
	my $self = shift;
	my $j = @_ ? \@_ : $self->{jobs};
	output $_->status_string for sort {$$a{id} <=> $$b{id}} @$j;
}

sub bg {
	my ($self, $id) = @_;
	my $j = $self->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting bg: $$j{id} == $j";
	$j->put_bg;
}

sub fg {
	my ($self, $id) = @_;
	my $j = $self->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting fg: $$j{id} == $j";
	$j->put_fg;
}

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
		my @k = @_ ? (grep exists $$self{_sighash}{$_}, @_) : (keys %{$$self{_sighash}});
		output [ map {sprintf '%2i) %s', $_, $$self{_sighash}{$_}} sort {$a <=> $b} @k ];
		return;
	}

	my $sig = '15'; # sigterm, the default
	if ($_[0] =~ /^--?(\w+)/) {
		if ( defined (my $s = $self->sig_by_spec($1)) ) {
			$sig = $s;
			shift;
		}
	}
	elsif ($_[0] eq '-s') {
		shift;
		$sig = $self->sig_by_spec(shift);
	}

	for (@_) {
		if (/^\%/) {
			my $j = $self->job_by_spec($_);
			CORE::kill($sig, -$j->{pgid});
		}
		else { CORE::kill($sig, $_) }
	}
}

sub disown { # dissociate job ... remove from @jobs, nohup
	todo 'see bash manpage for implementaion details';

	# is disowning the same as deamonizing the process ?
	# if it is, see man perlipc for example code

	# does this suggest we could also have a 'own' to hijack processes ?
	# all your pty are belong:0
}

# ############# #
# info routines #
# ############# #

sub job_by_id {
	my ($self, $id) = @_;
	for (@{$$self{jobs}}) { return $_ if $$_{id} eq $id }
	return undef;
}

sub job_by_spec {
	my ($self, $spec) = @_;
	return @{$$self{jobs}} ? $$self{jobs}[-1] : undef unless $spec;
	# see posix 1003.2 speculation for arbitrary cruft
	$spec = '%+' if $spec eq '%%' or $spec eq '%';
	$spec =~ /^ \%? (?: (\d+) | ([\+\-\?]?) (.*) ) $/x;
	my ($id, $q, $string) = ($1, $2, $3);
	if ($id) {
		for (@{$$self{jobs}}) { return $_ if $$_{id} == $id }
	}
	elsif ($q eq '+') { return $$self{jobs}[-1] if @{$$self{jobs}} }
	elsif ($q eq '-') { return $$self{jobs}[-2] if @{$$self{jobs}} > 1 }
	elsif ($q eq '?') {
		for (@{$$self{jobs}}) { return $_ if $$_{string} =~ /$string/ }
	}
	else { for (@{$$self{jobs}}) { return $_ if $$_{string} =~ /^\W*$string/ } } # match begin non strict
	return undef;
}

sub sig_by_spec {
	my ($self, $z) = @_;
	return $z if exists $$self{_sighash}{$z};
	$z =~ s{^(sig)?(.*)$}{uc($2)}ei;
	while (my ($k, $v) = each %{$$self{_sighash}}) {
		return $k if $v eq $z
	}
	return undef;
}


# ########### #
# Job objects #
# ########### #

package Zoidberg::Job;

use strict;
use IO::File;
use POSIX qw/:sys_wait_h :signal_h/;
use Zoidberg::Utils;

our @ISA = qw/Zoidberg::Contractor/;

sub exec { # like new() but runs immediatly
	my $self = ref($_[0]) ? shift : &new;
	$$self{pwd} = $ENV{PWD};
	local $ENV{ZOIDREF} = "$$self{shell}";

	my @re = eval { $self->run };
	$$self{shell}{error} = $@ || $$self{exit_status} || undef;
	complain if $@;
	if ($self->completed()) {
		$$self{shell}->broadcast('envupdate'); # FIXME breaks interface
		$$self{boss}->reinc_job($self) if @{ $$self{tree} };
	}

	if ( $$self{tree}[0] eq 'BGS' ) { # step over it - FIXME conflicts with fg_job
		shift @{$$self{tree}};
		my $ref = $$self{tree};
		$$self{tree} = [];
		$$self{boss}->shell_list(@$ref);
	}

	return @re;
}

sub new { # @_ should at least contain (tree=>$pipe, boss=>$ref) here
	shift; # class
	my $self = { id => 0, procs => [], @_ };
	$$self{shell} ||= $$self{boss}{shell};
	$$self{jobs}  ||= [];
	$$self{$_} = $$self{boss}{$_} for qw/_sighash terminal/; # FIXME check this

	while ( ref $$self{tree}[0] ) {
		my @b = $$self{shell}->parse_block(shift @{$$self{tree}});  # FIXME breaks interface, should be a hook
		if (@b > 1) { unshift @{$$self{tree}}, @b } # probably macro expansion
		else { push @{$$self{procs}}, @b }
	}
	$$self{bg}++ if $$self{tree}[0] eq 'BGS';

	return unless @{$$self{procs}}; # FIXME ugly
	debug 'blocks in job ', $$self{procs};
	my $pipe = @{$$self{procs}} > 1;
	$$self{string} ||= ($pipe ? '|' : '') . $$self{procs}[-1][0]{string}; # last one in the pipe is the one on screen

	my $meta = $$self{procs}[0][0];
	my $fork_job = $pipe
		|| ( defined($$meta{fork_job}) ? $$meta{fork_job} : 0 )
		|| $$self{bg} || $$self{capture} ;
	unless ($fork_job) { bless $self, 'Zoidberg::Job::builtin' }
	else { bless $self, 'Zoidberg::Job' }

	return $self;
}

sub round_up { 
	kill 1, -$_[0]->{pgid};
	$_->round_up() for @{$_[0]->{jobs}};
}

# ######## #
# Run code #
# ######## #

# As each process is forked, it should put itself in the new process group by calling setpgid
# The shell should also call setpgid to put each of its child processes into the new process 
# group. This is because there is a potential timing problem: each child process must be put 
# in the process group before it begins executing a new program, and the shell depends on 
# having all the child processes in the group before it continues executing. If both the child
# processes and the shell call setpgid, this ensures that the right things happen no matter 
# which process gets to it first.

# If the job is being launched as a foreground job, the new process group also needs to be 
# put into the foreground on the controlling terminal using tcsetpgrp. Again, this should be 
# done by the shell as well as by each of its child processes, to avoid race conditions.

sub run {
	my $self = shift;
	$$self{shell}{fg_job} = $self;

	$self->{tmodes}	= POSIX::Termios->new;

	$self->{procs}[-1][0]{last}++ unless $$self{capture};

	my ($pid, @pipe, $stdin, $stdout);
	my $zoidpid = $$;
	$stdin = fileno STDIN;

	# use pgid of boss when boss is part of a pipeline
	$$self{pgid} = $$self{boss}{pgid} unless $$self{shell}{settings}{interactive};

	my $i = 0;
	for my $proc (@{$self->{procs}}) {
		$i++;
		if ($$proc[0]{last}) { $stdout = fileno STDOUT }
		else { # open pipe to next process
			@pipe = POSIX::pipe;
			$stdout = $pipe[1];
		}

		$pid = fork; # fork process
		if ($pid) {  # parent process
			# set pid and pgid
			$$proc[0]{pid} = $pid;
			$self->{pgid} ||= $pid ;
			POSIX::setpgid($pid, $self->{pgid});
			debug "job \%$$self{id} part $i has pid $pid and pgid $$self{pgid}";
			# set terminal control
			POSIX::tcsetpgrp($self->{shell}{terminal}, $self->{pgid}) 
				if $$self{shell}{settings}{interactive} && ! $$self{bg};
		}
		else { # child process
			# set pgid
			$self->{pgid} ||= $$; # after first pgid is set allready
			POSIX::setpgid($$, $self->{pgid});
			# set terminal control
			POSIX::tcsetpgrp($self->{shell}{terminal}, $self->{pgid}) 
				if $$self{shell}{settings}{interactive} && ! $$self{bg};
			# and run child
			$ENV{ZOIDPID} = $zoidpid;
			eval { $self->_run_child($proc, $stdin, $stdout) };
			exit complain || 0; # exit child process
		}

		POSIX::close($stdin)  unless $stdin  == fileno STDIN ;
		POSIX::close($stdout) unless $stdout == fileno STDOUT;
		$stdin = $pipe[0] unless $$proc[0]{last} ;
	}

	my @re  = $$self{bg}      ? $self->put_bg
		: $$self{capture} ? ($self->_capture($stdin)) : $self->put_fg ;
 
	# postrun
	POSIX::tcsetpgrp($$self{shell}{terminal}, $$self{shell}{pgid});

	return @re;
}

sub _capture { # called in parent when capturing
	my ($self, $stdin) = @_;
	local $/ = $ENV{RS}
		if exists $ENV{RS} and defined $ENV{RS}; # Record Separator
	debug "capturing output from fd $stdin, \$/ = '$/'";
	open IN, "<&=$stdin"; # open file descriptor
	my @re = (<IN>);
	close IN;
	POSIX::close($stdin)  unless $stdin  == fileno STDIN ;
	error if $self->{procs}[-1][0]->{exit_status};
	return @re;
}

sub _run_child { # called in child process
	my $self = shift;
	my ($block, $stdin, $stdout) = @_;

	$self->{shell}{round_up} = 0; # FIXME this bit has to many use
	$self->{shell}{settings}{interactive} = 0; # idem
	map { $SIG{$_} = 'DEFAULT' } qw{INT QUIT TSTP TTIN TTOU};

	# make sure stdin and stdout are right, else dup them
	for ([$stdin, fileno STDIN], [$stdout, fileno STDOUT]) {
		next if $_->[0] == $_->[1];
		POSIX::dup2(@$_);
		POSIX::close($_->[0]);
	}

	# do redirections and env
	$self->do_redirect($block);
	$self->do_env($block);

    	$self->{shell}->silent;

	# here we go ... finally
	$self->{shell}{eval}->_eval_block($block);
}

# ################ #
# Redirection code #
# ################ #

sub do_redirect {
	my ($self, $block) = @_;
	my @save_fd;
	for my $fd (keys %{$block->[0]{fd}}) {
		my @opt = @{$block->[0]{fd}{$fd}};
		debug "redirecting fd $fd to $opt[1]$opt[0]";
		my $fh = ref($opt[0]) ? $opt[0] : IO::File->new(@opt);
		# FIXME support for >& use IO::Handle for that
		error "Failed to open $opt[1]$opt[0]" unless $fh;
		push @save_fd, [POSIX::dup($fd), $fd];
		POSIX::dup2($fh->fileno, $fd);
		POSIX::close($fh->fileno);
	}
	return \@save_fd;
}

sub undo_redirect {
	my $save_fd = pop;
	for (@$save_fd) {
		POSIX::dup2(@$_);
		POSIX::close($_->[0]);
	}
}

# ######## #
# env code #
# ######## #

sub do_env {
	my ($self, $block) = @_;
	my @save_env;
	while (my ($env, $val) = each %{$$block[0]{env}}) {
		debug "env $env, val $val";
		push @save_env, [$env, $ENV{$env}];
		$ENV{$env} = $val;
	}
	return \@save_env;
}

sub undo_env {
	my $save_env = pop;
	$ENV{$$_[0]} = $$_[1] for @$save_env;
}

# ########### #
# Signal code #
# ########### #

sub put_fg {
	my $self = shift;

	message $self->status_string('Running') if $self->{bg};
 	$self->{bg} = 0;

	@{$$self{boss}{jobs}} = grep {$_ ne $self} @{$$self{boss}{jobs}};
	$$self{shell}{fg_job} = $self;

	POSIX::tcsetpgrp($self->{shell}{terminal}, $self->{pgid})
		if $self->{shell}{settings}{interactive};

	if ($self->{stopped}) {
		kill(SIGCONT, -$self->{pgid});
		$self->{stopped} = 0;
	}
	$self->wait_job;

	POSIX::tcsetpgrp($self->{shell}{terminal}, $self->{shell}{pgid})
		if $self->{shell}{settings}{interactive};
	
	if ($$self{stopped} or $$self{terminated}) {
		if ($$self{stopped} and $$self{shell}{settings}{notify_verbose}) {
			$$self{shell}->jobs();
		}
		else {
			message $self->status_string;
		}
	}

	$$self{shell}{error} = $$self{exit_status}; # FIXME clean up for this - see where evel goes n stuff
	if ($self->completed()) {
		$$self{shell}->broadcast('envupdate'); # FIXME breaks interface
		$$self{boss}->reinc_job($self) if @{ $$self{tree} };
	}
}

sub put_bg {
	my $self = shift;
	$self->_put_bg;

	if ($self->{stopped}) {
		kill(SIGCONT, -$self->{pgid});
		$self->{stopped} = 0;
	}

	message $self->status_string('Running');
}

sub _put_bg {
	my $self = shift;

	unless ($$self{id}) {
		$$_{id} > $$self{id} and $$self{id} = $$_{id} for @{$$self{boss}{jobs}};
		$$self{id}++;
	}

	@{$$self{boss}{jobs}} = grep {$_ ne $self} @{$$self{boss}{jobs}};
	push @{$$self{boss}{jobs}}, $self;

	$self->{bg} = 1;
}

sub wait_job {
	my $self = shift;
	while ( ! $self->{stopped} && ! $self->completed ) {
		my $pid;
		until ($pid) {
			$pid = waitpid(-$self->{pgid}, WUNTRACED|WNOHANG);
			$self->{shell}->broadcast('poll_socket');
			select(undef, undef, undef, 0.001);
		}
		$self->_update_child($pid, $?);
	}
}

sub update_status {
	my $self = shift;
	my $pid;
	while ($pid = waitpid(-$self->{pgid}, WUNTRACED|WNOHANG)) {
		$self->_update_child($pid, $?);
		last unless $pid > 0;
	}
}

sub completed { ! grep { ! $$_[0]{completed} } @{$_[0]{procs}} }

sub _update_child {
	my ($self, $pid, $status) = @_;
	return unless $pid; # 0 == all is well
	debug "pid: $pid returned: $status";

	if ($pid == -1) { # -1 == all processes in group ended
		kill( 15 => -$self->{pgid} ); # SIGTERM just to be sure
		debug "group $$self{pgid} has disappeared:($!)";
		$$_[0]{completed}++ for @{$self->{procs}};
	}
	else {
		my ($child) = grep {$$_[0]{pid} == $pid} @{$$self{procs}};
		bug "Don't know this pid: $pid" unless $child;
		$$child[0]{exit_status} = $status;
		if (WIFSTOPPED($status)) {
			$$self{stopped} = 1;
			(WSTOPSIG($status) == 22 or WSTOPSIG($status) == 21 ) # SIGTT(IN|OUT)
				? $self->put_fg : $self->_put_bg;
		}
		else {
			$$child[0]{completed} = 1;
			if ($pid == $$self{procs}[-1][0]{pid}) { # the end of the line ..
				$$self{exit_status} = $status;
				$$self{terminated}++ if WIFSIGNALED($status);
				unless ($self->completed) {
					local $SIG{PIPE} = 'IGNORE';
					kill( 13 => -$$self{pgid} ); # SIGPIPE
				}
			}
		}
	}
}

# ############ #
# Notification #
# ############ #

sub status_string {
	# POSIX: "[%d]%c %s %s\n", <job-number>, <current>, <status>, <job-name>
	my $self = shift;

	my $pref = '';
	if ($$self{id}) {
		$pref = "[$$self{id}]" . (
			($self eq $$self{boss}{jobs}[-1]) ? '+ ' :
			($self eq $$self{boss}{jobs}[-2]) ? '- ' : '  ' );
	}

	my $status ||=
		$$self{stopped}    ? 'Stopped'    :
		$$self{terminated} ? 'Terminated' :
		$$self{completed}  ? 'Done'       : 'Running' ;

	my $string = $$self{string};
	$string =~ s/\n$//;
	$string .= "\t\t(pwd: $$self{pwd})" unless $$self{pwd} eq $ENV{PWD};

	return $pref . $status . "\t$string";
}

package Zoidberg::Job::builtin;

use strict;
use Zoidberg::Utils;

our @ISA = qw/Zoidberg::Job/;

sub round_up { $_->round_up() for @{$_[0]->{jobs}} }

sub run {
	my $self = shift;
	my $block = $self->{procs}[0];
	$$self{shell}{fg_job} = $self;

	my $saveint = $SIG{INT};
	if ($self->{settings}{interactive}) {
		my $ii = 0;
		$SIG{INT} = sub {
			if (++$ii < 3) { message "[$$self{id}] instruction terminated by SIGINT" }
			else { die "Got SIGINT 3 times, killing native scuddle\n" }
		};
	}
	else { $SIG{INT} = sub { die "[SIGINT]\n" } }

	# do redirections and env
	my $save_fd = $self->do_redirect($block);
	my $save_env = $self->do_env($block);

	# here we go !
	eval { $self->{shell}{eval}->_eval_block($block) }; # VUNZig om hier een eval te moeten gebruiken

	# restore file descriptors and env
	$self->undo_redirect($save_fd);
	$self->undo_env($save_env);

	# restore other stuff
	$SIG{INT} = $saveint;
	$self->{completed}++;
	
	die if $@;
}

sub put_bg { error q#Can't put builtin in the background# }
sub put_fg { error q#Can't put builtin in the foreground# }

sub completed { $_[0]->{completed} }

1;

__END__

=head1 NAME

Zoidberg::Contractor - Module to manage jobs

=head1 SYNOPSIS

	use Zoidberg::Contractor;
	my $c = Zoidberg::Contractor->new();
	
	$c->shell_list( [qw(cat ./log)], '|', [qw(grep -i error)] );

=head1 DESCRIPTION

Zoidberg inherits from this module, it manages jobs.

It uses Zoidberg::StringParser and Zoidberg::Eval.

Also it defines Zoidberg::Job and subclasses.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::StringParser>, L<Zoidberg::Eval>

=head1 AUTHORS

Jaap Karssenberg, E<lt>pardus@cpan.orgE<gt>

Raoul Zwart, E<lt>rlzwart@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Jaap Karssenberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

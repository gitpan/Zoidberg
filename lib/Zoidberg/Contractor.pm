package Zoidberg::Contractor;

our $VERSION = '0.50';

use strict;
use POSIX ();
use Config;
use Zoidberg::Utils;
use Zoidberg::Eval;

sub new {
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

	## add some commands
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
		# Put ourselves in our own process group, just to be sure.
		#$self->{pgid} = $$;
		#POSIX::setpgid(0, $self->{pgid}); # fails for login shell
		
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
	my ($self, $meta, @list) = grep {defined $_} @_;

	return $$self{shell}{fg_job}->shell_list($meta, @list)
		if $$self{shell}{fg_job} && $self ne $$self{shell}{fg_job};
	my $save_fg_job = $$self{shell}{fg_job}; # could be ubdef

	unless (ref($meta) eq 'HASH' and @list) { # wasn't really meta
		unshift @list, $meta;
		undef $meta;
	}
	else { return unless @list }
	$$self{queue} = \@list;
	my @re;
	my ($prev_sign, @chunk) = ('', $self->_next_chunk);
	%{$chunk[0][0][0]} = (%{$chunk[0][0][0]}, %$meta) if defined $meta;
	while (@chunk) { # @chunk = pipe, sign
		# mind that logic grouping for AND and OR isn't the same, OR is stronger
		if ($$self{shell}{error} ? ($prev_sign eq 'AND') : ($prev_sign eq 'OR')) {
			my $i;
			++$i and @chunk = $self->_next_chunk
				while @chunk and ! grep {$_ eq $chunk[1]} qw/EOL EOS BGS OR/;
			$prev_sign = $chunk[1];
			debug "skipped $i chunks";
		}
		else {
			debug 'going to do chunk: ', $chunk[0];
			$prev_sign = $chunk[1];
			if (@{$chunk[0]}) {
				@re = Zoidberg::Job->exec(
					boss => $self,
					tree => $chunk[0],
					bg   => $chunk[1] eq 'BGS', );
				$$self{shell}->broadcast('envupdate');
			}
		}
		@chunk = $self->_next_chunk;
	}

	$$self{shell}{fg_job} = $save_fg_job;
	return @re;
}

sub _next_chunk {
	my ($self, $skip) = @_;
	my @r;
	my $ref = $$self{queue};
	unless (@$ref) {
#		@$ref = $self->pull_blocks();
		return unless @$ref;
	}
	while ( @$ref && ! grep {$_ eq $$ref[0]} qw/AND OR EOS EOL BGS/ ) {
		my $b = shift @$ref;
		$b = (!$skip && ref $b) ? $$self{shell}->parse_block($b, $$self{queue}) : $b;
		push @r, $b if defined $b;
	}
	my $sign = @$ref ? shift @$ref : '' ;
	return \@r, $sign;
}

# ############ #
# Job routines #
# ############ #

sub jobs { 
	my $self = shift;
	my $j = @_ ? \@_ : $self->{jobs};
	if (@$j) { output $_->status_string for sort {$$a{id} <=> $$b{id}} @$j }
	else { message "No jobs" } # message won't show in pipeline
}

sub bg {
	my ($self, $id) = @_;
	my $j = $self->_job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting bg: $$j{id} == $j";
	$j->put_bg;
}

sub fg {
	my ($self, $id) = @_;
	my $j = $self->_job_by_spec($id)
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
		if ( defined (my $s = $self->_sig_by_spec($1)) ) {
			$sig = $s;
			shift;
		}
	}
	elsif ($_[0] eq '-s') {
		shift;
		$sig = $self->_sig_by_spec(shift);
	}

	for (@_) {
		if (/^\%/) {
			my $j = $self->_job_by_spec($_);
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

# ################## #
# Internal interface #
# ################## #

sub _job_by_id {
	my ($self, $id) = @_;
	for (@{$$self{jobs}}) { return $_ if $$_{id} eq $id }
	return undef;
}

sub _job_by_spec {
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

sub _sig_by_spec {
	my ($self, $z) = @_;
	return $z if exists $$self{_sighash}{$z};
	$z =~ s{^(sig)?(.*)$}{uc($2)}ei;
	while (my ($k, $v) = each %{$$self{_sighash}}) {
		return $k if $v eq $z
	}
	return undef;
}

sub reap_jobs {
	my $self = shift;
	my (@completed, @running);
	for ( @{$self->{jobs}} ) {
		$_->update_status;
		if ($_->completed) { push @completed, $_ }
		else { push @running, $_ }
	}
	$self->{jobs} = \@running;
	debug 'reaping jobs, body count: '.scalar(@completed);
	if ($$self{shell}{settings}{interactive}) {
		++$$_{completed} and message $_->status_string
			for sort {$$a{id} <=> $$b{id}} grep {! $$_{no_notify}} @completed;
	}
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
	$$self{shell}{error} = $@ || $$self{status} || undef;
	complain if $@;

	return @re;
}

sub new { # @_ should at least contain (tree=>$pipe, boss=>$ref) here
	shift; # class
	my $self = { id => 0, @_ };
	my $pipe = @{$$self{tree}} > 1;
	$$self{string} ||= ($pipe ? '|' : '') . $$self{tree}[-1][0]{string};
		# last one in the pipe is the one on screen
	$$self{shell} ||= $$self{boss}{shell};
	$$self{jobs}  ||= [];
	$$self{$_} = $$self{boss}{$_} for qw/_sighash terminal/; # FIXME check this

	my $meta = $$self{tree}[0][0];
	my $fork_job = $pipe
		|| ( defined($$meta{fork_job}) ? $$meta{fork_job} : 0 )
		|| $$self{bg}
		|| $$meta{capture} ;
	unless ($fork_job) { bless $self, 'Zoidberg::Job::builtin' }
#	elsif ( grep {! ref $_} @{$self->{tree}}) { bless $self, 'Zoidberg::Job::meta' }
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
	# fixme procs and tree can be merged
	$self->{procs} = [ map {block => $_, completed => 0, stopped => 0}, @{$self->{tree}} ];

	my $capture = $self->{tree}[0][0]{capture};
	$self->{procs}[-1]{last}++ unless $capture;

	my ($pid, @pipe, $stdin, $stdout);
	my $zoidpid = $$;
	$stdin = fileno STDIN;

	# use pgid of boss when boss is part of a pipeline
	$$self{pgid} = $$self{boss}{pgid} unless $$self{shell}{settings}{interactive};

	my $i = 0;
	for my $proc (@{$self->{procs}}) {
		$i++;
		if ($proc->{last}) { $stdout = fileno STDOUT }
		else { # open pipe to next process
			@pipe = POSIX::pipe;
			$stdout = $pipe[1];
		}

		$pid = fork; # fork process
		if ($pid) {  # parent process
			# set pid and pgid
			$proc->{pid} = $pid;
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
		$stdin = $pipe[0] unless $proc->{last} ;
	}

	my @re  = $$self{bg} ? $self->put_bg
		: $capture   ? ($self->_capture($stdin)) : $self->put_fg ;
 
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
	error if $self->{procs}[-1]->{status};
	return @re;
}

sub _run_child { # called in child process
	my $self = shift;
	my ($proc, $stdin, $stdout) = @_;

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
	$self->do_redirect($proc->{block});
	$self->do_env($proc->{block});

    	$self->{shell}->silent;

	# here we go ... finally
	$self->{shell}{eval}->_eval_block($proc->{block});
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

sub completed { ! grep { ! $_->{completed} } @{$_[0]->{procs}} }

sub _update_child {
	my ($self, $pid, $status) = @_;
	return unless $pid; # 0 == all is well
	debug "pid: $pid returned: $status";

	if ($pid == -1) { # -1 == all processes in group ended
		kill( 15 => -$self->{pgid} ); # SIGTERM just to be sure
		debug "group $$self{pgid} has disappeared:($!)";
		$_->{completed}++ for @{$self->{procs}};
	}
	else {
		my ($child) = grep {$$_{pid} == $pid} @{$$self{procs}};
		bug "Don't know this pid: $pid" unless $child;
		$$child{status} = $status;
		if (WIFSTOPPED($status)) {
			$$self{stopped} = 1;
			(WSTOPSIG($status) == 22 or WSTOPSIG($status) == 21 ) # SIGTT(IN|OUT)
				? $self->put_fg : $self->_put_bg;
		}
		else {
			$$child{completed} = 1;
			if ($pid == $$self{procs}[-1]{pid}) { # the end of the line ..
				$$self{status} = $status;
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
	my ($self, $status) = @_;

	my $pref = '';
	if ($$self{id}) {
		$pref = "[$$self{id}]" . (
			($self eq $$self{boss}{jobs}[-1]) ? '+ ' :
			($self eq $$self{boss}{jobs}[-2]) ? '- ' : '  ' );
	}

	$status ||=
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
	my $block = $self->{tree}[0];
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

=cut

package Zoidberg::Job::meta;

use strict;
use vars qw/$AUTOLOAD/;
use Zoidberg::Utils;

# sign: XF ==> Xargs Forward
#       XB <== Xargs Backwards

our @ISA = qw/Zoidberg::Job/;

sub run {
	my $self = shift;
	todo "Fancy background job" if $self->{bg};
	my ($pipe, $sign, @args);
	while (
		scalar(@{$self->{tree}}) and
		($pipe, $sign) = $self->_next_statement($self->{tree})
	) {
		todo "Backward argument redirection" if $sign eq 'XB';
		@args = $self->exec_job($pipe);
	}
}

sub _next_statement {
	my ($self, $ref) = @_;
	my @r;
	return undef unless scalar(@$ref);
	while (
		scalar(@$ref) &&
		! grep {$_ eq $ref->[0]} qw/XF XB/
	) { push @r, shift @$ref }
	my $sign = scalar(@$ref) ? shift(@$ref) : '' ;
	return \@r, $sign;
}

sub exec_job {
	my ($self, $pipe) = shift;
	$self->{jobs} ||= [];
	Zoidberg::Job->exec(
		tree => $pipe,
		zoid => $self->{shell},
		jobs => $self->{jobs},
	);
}

sub put_bg { error q#Can't put builtin in the background# }
sub put_fg { error q#Can't put builtin in the foreground# }

sub completed {
	my $self = shift;
	# ! jobs_left ||
	! grep {!$_->completed} @{$self->{jobs}};
}

=cut

1;

__END__

=head1 NAME

Zoidberg::Contractor - Module to manage jobs

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

This module is not intended for external use ... yet.
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

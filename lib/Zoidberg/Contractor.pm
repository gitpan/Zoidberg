package Zoidberg::Contractor;

our $VERSION = '0.41';

use strict;
use POSIX ();
use Config;
use Zoidberg::Utils qw/:error :output/;
use Zoidberg::Eval;

sub new { init(bless {}, shift) }

sub init {
	my $self = shift;

	## add some commands and events
	$self->{commands}{$_} = $_  for qw/fg bg kill jobs/;
	$self->{events}{precmd} = '->reap_jobs';

	## jobs stuff
	$self->{jobs} = [];
	$self->{_sighash} = {};
	$self->{terminal} = fileno(STDIN);

	my @sno = split/[, ]/,$Config{sig_num};
	my @sna = split/[, ]/,$Config{sig_name};
	$self->{_sighash}{$sno[$_]} = $sna[$_] for (0..$#sno);

	if ($self->{settings}{interactive}) { # FIXME bad for recursiveness
		# Loop until we are in the foreground.
		while (POSIX::tcgetpgrp($self->{terminal}) != ($self->{pgid} = getpgrp)) {
			kill (21, -$self->{pgid}); # SIGTTIN , 
			# not using constants to prevent namespace pollution
		}
		# ignore interactive and job control signals
		$SIG{$_} = 'IGNORE' for qw/INT QUIT TSTP TTIN TTOU/;
		# Put ourselves in our own process group, just to be sure.
		$self->{pgid} = $$;
		POSIX::setpgid(0, $self->{pgid});
		# And get terminal control
		POSIX::tcsetpgrp($self->{terminal}, $self->{pgid});
		$self->{tmodes} = POSIX::Termios->new;
		$self->{tmodes}->getattr;
	}

	## setup eval namespace
	$self->{eval} = Zoidberg::Eval->_new($self);

	return $self;
}

sub round_up { # FIXME usage of procs is not transparent
	kill(1, -$_->{pgid})
		for grep { $_->{procs} } @{$_[0]->{jobs}};
}

sub shell_job { todo }

sub shell_list {
	my ($self, @list) = @_;
	return unless grep {defined $_} @list;
	my $prev_sign = '';
	while (@list) {
		my ($pipe, $sign) = $self->_next_statement(\@list);
		if ( defined($self->{error}) ? ($prev_sign eq 'AND') : ($prev_sign eq 'OR') ) {
			$prev_sign = $sign if $sign =~ /^(EOS|BGS)$/;
			next;
		}
		else {
			$prev_sign = $sign;
			next unless @$pipe; # skipping empty pipes
			Zoidberg::Job->exec(
				tree => $pipe,
				zoid => $self,
				bg   => ($sign eq 'BGS'),
			);
		}
	}
}

our @_logic_signs = qw/AND OR EOS BGS/; # && || ; &

sub _next_statement {
	my ($self, $ref) = @_;
	my @r;
	return undef unless scalar(@$ref);
	while (
		scalar(@$ref) &&
		! grep {$_ eq $ref->[0]} @_logic_signs
	) { push @r, shift @$ref }
	my $sign = scalar(@$ref) ? shift @$ref : '' ;
	return \@r, $sign;
}

# ############ #
# Job routines #
# ############ #

sub jobs { 
	my $self = shift;
	my $j = scalar(@_) ? \@_ : $self->{jobs};
	$_->print_status for grep {$_->{bg} || $_->{stopped}} @$j;
}

sub bg {
	my ($self, $id) = @_;
	my $j = defined($id)
		? $self->_job_by_spec($id)
		: $self->_current_job;

	error 'No such job'.($id ? ": $id" : '') unless ref $j;
	$j->put_bg;
}

sub fg {
	my ($self, $id) = @_;
	my $j = defined($id)
		? $self->_job_by_spec($id)
		: $self->_current_job;

	error 'No such job'.($id ? ": $id" : '') unless ref $j;
	$j->put_fg;
}

sub kill {
	my $self = shift;
	# from bash-2.05/builtins/kill.def:
	# kill [-s sigspec | -n signum | -sigspec] [pid | job]... or kill -l [sigspec]
	# Send the processes named by PID (or JOB) the signal SIGSPEC.  If
	# SIGSPEC is not present, then SIGTERM is assumed.  An argument of `-l'
	# lists the signal names; if arguments follow `-l' they are assumed to
	# be signal numbers for which names should be listed.  Kill is a shell
	# builtin for two reasons: it allows job IDs to be used instead of
	# process IDs, and, if you have reached the limit on processes that
	# you can create, you don't have to start a process to kill another one.
	if ($_[0] eq '-l') {
		shift;
		my @l;
		if (@_) { @l = @_ }
		else { @l = sort keys %{$self->{_sighash}} }
		for (@l) {
			print "$_) $self->{_sighash}{$_}\n"
				if exists $self->{_sighash}{$_}
		}
		return;
	}
	return unless defined $_[0];
	my $sig = '15';
	if ($_[0] =~ /^-?(\d+)$/ or $_[0] =~ /^-?([a-z\d]+)$/i) {
		# this _could_ be a sigspec
		if ( defined( my $s = $self->_sig_by_spec($1) ) ) {
			$sig = $s;
			shift;
		}
	}
	elsif ($_[0] eq '-s') {
		shift;
		$sig = $self->_sig_by_spec(shift);
	}
	foreach my $p (@_) {
		my $j = $self->_job_by_spec($p);
		if (ref($j)) {
			CORE::kill($sig,-$j->{pgid});
		}
		elsif ($j =~ /^-?\d+/) {
			CORE::kill($sig,$p);
		}
		else { error("No such job: $p") }
	}
}

sub _sig_by_spec {
	my ($self, $z) = @_;
	if ($z =~ /\D/) {
		$z =~ s{^(sig)?(.*)$}{uc($2)}ei;
		while (my ($k, $v) = each %{$self->{_sighash}}) {
			return $k if $v eq $z
		}
	}
	else { return $z if exists $self->{_sighash}{$z} }
	return undef;
}

sub _job_by_spec {
	my ($self, $spec) = @_;
	# see posix 1003.2 speculation for arbitrary cruft
	if ($spec =~ /^ \% (?: (\d+) | (\??) (.*) ) $/x) {
		my $m = $3;
		if ($1) {
			for (@{$self->{jobs}}) { return $_ if $_->{id} == $1 }
		}
		elsif ($2) { # command begins with $3
			for (@{$self->{jobs}}) { return if $_->{string} =~ /^$m/ }
		}
		elsif ($m eq '%' or $m eq '+') { return $self->{jobs}[-1] if scalar @{$self->{jobs}} }
		elsif ($m eq '-') { return $self->{jobs}[-2] if scalar(@{$self->{jobs}}) > 1 }
		else { # command contains $3
			for (@{$self->{jobs}}) { return if $_->{string} =~ /$m/ }
		}
	}
	return $spec;
}

sub disown { # dissociate job ... remove from @jobs, nohup
	my $self = shift;
	my $id = shift;
	unless ($id) {
		my @jobs = grep { ($_->{bg}) || ($_->{stopped}) } @{$self->{jobs}};
		error "No background job!" unless scalar @jobs;
		if (scalar(@jobs) == 1) { $id = $jobs[0]->{id} }
		else { error "Which job?" }
	}
	my $job = $self->_jobbyid($id);
	error "No such job: $id" unless $job;
	todo 'see bash manpage for implementaion details';

	# is disowning the same as deamonizing the process ?
	# if it is, see man perlipc for example code

	# does this suggest we could also have a 'own' to hijack processes ?
	# all your pty are belong:0
}

# ################## #
# Internal interface #
# ################## #

sub _sigspec {
    my $self = shift;
    my $sig = shift;
    if ($sig =~ /^-(\d+)$/) {
        my $num = $1;
        if (grep{$_==$num}keys%{$self->{_sighash}}) { return $num }
        else { return }
    }
    elsif ($sig =~ /^-?([a-z]+)$/i) {
        my $name=uc($1);
        if (my($num)=grep{$self->{_sighash}{$_} eq $name}keys%{$self->{_sighash}}) {
            return $num;
        }
        else { return }
    }
    return;
}

sub _jobbyid {
    my ($self, $id) = @_;
    ( grep {$_->{id} == $id} @{$self->{jobs}} )[0];
}

sub _current_job {
	my $self = shift;
	my @r = ( reverse grep {$_->{stopped} || $_->{bg}} @{$self->{jobs}} )[0,1];
	return( wantarray ? @r : $r[0] );
}

sub reap_jobs {
	my $self = shift;
	debug 'gonna reap me some jobs';
	my (@completed, @running);
	for ( @{$self->{jobs}} ) {
		$_->update_status;
		if ($_->completed) { push @completed, $_ }
		else { push @running, $_ }
	}
	$self->{jobs} = \@running;
	$_->print_status($_->{terminated} ? 'Terminated' : 'Done') for grep {$_->{bg}} @completed;
}

package Zoidberg::Job;

use strict;
use IO::File;
use POSIX qw/:sys_wait_h :signal_h/;
use Zoidberg::Utils qw/:error debug/;

sub exec { # like new() but runs immediatly
	my $self = ref($_[0]) ? shift : &new;

	eval { $self->run };
	$@ ? complain : undef $self->{zoid}{error};

	return $self->{id};
}

sub new { # @_ should at least contain (tree=>$pipe, zoid=>$ref) here
	shift; # class
	my $self = {@_};
	my $jobs = delete $self->{jobs} || $self->{zoid}{jobs};
	$self->{id} = (
		scalar(@$jobs)
		? $$jobs[-1]->{id}
		: 0
	) + 1;
	$self->{string} = $self->{tree}[0][0]{string}; # FIXME something better ?

	unless ( # FIXME vunzige code
		@{$self->{tree}} != 1
		or $self->{bg}
		or $self->{zoid}{round_up}
			&& ( $self->{tree}[0][0]{fork_job}
				|| $self->{tree}[0][0]{context} eq 'SH' )
	) { bless $self, 'Zoidberg::Job::builtin' }
	elsif ( grep {! ref $_} @{$self->{tree}}) { bless $self, 'Zoidberg::Job::meta' }
	else { bless $self, 'Zoidberg::Job' }

	push @$jobs, $self;
	return $self;
}

sub zoid { $_[0]->{zoid} }

# ######## #
# Run code #
# ######## #

sub run {
	my $self = shift;
	$self->{tmodes}	= POSIX::Termios->new;
	$self->{procs} = [ map {block => $_, completed => 0, stopped => 0}, @{$self->{tree}} ];
	$self->{procs}[-1]{last}++;

	my ($pid, @pipe, $stdin, $stdout);
	my $zoidpid = $$;
	$stdin = fileno STDIN;

	for my $proc (@{$self->{procs}}) {
		unless ($proc->{last}) { # open pipe to next process
			@pipe = POSIX::pipe;
			$stdout = $pipe[1];
		}
		else { $stdout = fileno STDOUT }

		$pid = fork; # fork process
		if ($pid) {  # parent process
			$proc->{pid} = $pid;
			# we take pid from first process and put 
			# all others in that group
			$self->{pgid} ||= $pid ;
			POSIX::setpgid($pid, $self->{pgid});
		}
		else { # child process
			$self->{pgid} ||= $$; # after first pgid is set allready
			$self->{zoid}{round_up} = 0; # FIXME this bit has to many uses
			$ENV{ZOIDPID} = $zoidpid;
			eval { $self->_run_child($proc, $stdin, $stdout) };
			exit complain || 0; # exit child process
		}

		POSIX::close($stdin)  unless $stdin  == fileno STDIN ;
		POSIX::close($stdout) unless $stdout == fileno STDOUT;
		$stdin = $pipe[0] unless $proc->{last} ;
	}
	$self->{bg} ? $self->put_bg : $self->put_fg;
 
	# postrun
	POSIX::tcsetpgrp($self->{zoid}{terminal}, $self->{zoid}{pgid});
	my $exit_status = $self->{procs}[-1]->{status};
	error {printed => 1}, $exit_status if $exit_status; # silent error
}

sub _run_child {
	my $self = shift;
	my ($proc, $stdin, $stdout) = @_;

	if ($self->{zoid}{settings}{interactive}) {
		# get terminal control and set signals
		POSIX::tcsetpgrp($self->{zoid}{terminal}, $self->{pgid}) unless $self->{bg};
		map { $SIG{$_} = 'DEFAULT' } qw{INT QUIT TSTP TTIN TTOU CHLD};
	}

	# make sure stdin and stdout are right, else dup them
	for ([$stdin, fileno STDIN], [$stdout, fileno STDOUT]) {
		next if $_->[0] == $_->[1];
		POSIX::dup2(@$_);
		POSIX::close($_->[0]);
	}

	# do redirections
	$self->do_redirect($proc->{block});

	$self->{zoid}{settings}{interactive} = 0 unless -t STDOUT;
    	$self->{zoid}->silent;

	# here we go ... finally
	$self->{zoid}{eval}->_eval_block($proc->{block});
}

# ################ #
# Redirection code #
# ################ #

sub do_redirect {
	my ($self, $block) = @_;
	my @save_fd;
	for my $fd (keys %{$block->[0]{fd}}) {
		my @opt = @{$block->[0]{fd}{$fd}};
		($opt[0]) = $self->{zoid}{eval}->$_($opt[0])
			for @Zoidberg::Eval::_shell_expand;
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

# ########### #
# Signal code #
# ########### #

sub put_fg {
	my ($self, $cont) = @_;
	$self->print_status('Running') if $self->{bg};
 	$self->{bg} = 0;

	POSIX::tcsetpgrp($self->{zoid}{terminal}, $self->{pgid})
		if $self->{zoid}{settings}{interactive};

	if ($cont || $self->{stopped}) {
		kill(SIGCONT, -$self->{pgid});
		$self->{stopped} = 0;
	}
	$self->wait_job;

	POSIX::tcsetpgrp($self->{zoid}{terminal}, $self->{zoid}{pgid})
		if $self->{zoid}{settings}{interactive};
}

sub put_bg {
	my ($self, $cont) = @_;
	$self->{bg} = 1;

	if ($cont || $self->{stopped}) {
		kill(SIGCONT, -$self->{pgid});
		$self->{stopped} = 0;
	}

	$self->print_status('Running');
}

sub wait_job {
	my $self = shift;
	while ( ! $self->{stopped} && ! $self->completed ) {
		my $pid;
		until ($pid) {
			$pid = waitpid(-$self->{pgid}, WUNTRACED|WNOHANG);
			$self->{zoid}->broadcast_event('poll_socket');
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

	if ($pid == -1) { # -1 == all processes in groupd ended
		my $r = kill(0,-$self->{pgid});
		unless ($r > 0 or ! $!{ESRCH}) { # `No such process' (zombie)
			debug "$self->{pgid} has disappeared:($!)";
			$_->{completed}++ for @{$self->{procs}};
		}
	}
	else {
		my ($child) = grep {$_->{pid} == $pid} @{$self->{procs}};
		$self->{status} = $child->{status} = $status;
		if (WIFSTOPPED($status)) {
			$self->{stopped} = 1;
			$self->put_fg('FORCE')
				if WSTOPSIG($status) == 22	# SIGTTIN
				or WSTOPSIG($status) == 21 ;	# SIGTTOU
		}
		else { 
			$self->{terminated}++ if WIFSIGNALED($status);
			$child->{completed} = 1
		}
	}
}

# ############ #
# Notification #
# ############ #

sub print_status {
	# POSIX: "[%d]%c %s %s\n", <job-number>, <current>, <status>, <job-name>
	my ($self, $status) = @_;

	my @c = $self->{zoid}->_current_job;
	my $current =
		($self eq $c[0]) ? '+' : 
		($self eq $c[1]) ? '-' : ' ' ;

	$status ||= $self->{stopped} ? 'Stopped' : 'Running' ;

	my $string = $self->{string};
	$string =~ s/\n$//;
	print "[$$self{id}]$current $status\t$string\n"; # FIXME shouldn't this be message ?
}

package Zoidberg::Job::builtin;

use strict;
use Zoidberg::Utils qw/:error message/;

our @ISA = qw/Zoidberg::Job/;

sub run {
	my $self = shift;
	my $block = $self->{tree}[0];

	# prepare some stuff
	$self->{saveint} = $SIG{INT};
	if ($self->{settings}{interactive}) {
		my $ii = 0;
		$SIG{INT} = sub {
			if (++$ii < 3) { message "[$$self{id}] instruction terminated by SIGINT" }
			else { die "Got SIGINT 3 times, killing native scuddle\n" }
		};
	}
	else { $SIG{INT} = sub { die "[SIGINT]\n" } }

	# do redirections
	my $save_fd = $self->do_redirect($block);

	# here we go !
	eval { $self->{zoid}{eval}->_eval_block($block) }; # VUNZig om hier een eval te moeten gebruiken
	die if $@; 

	# restore file descriptors
	$self->undo_redirect($save_fd);

	# restore other stuff
	$SIG{INT} = delete $self->{saveint};
	$self->{completed}++;
}

sub put_bg { error q#Can't put builtin in the background# }
sub put_fg { error q#Can't put builtin in the foreground# }

sub completed { $_[0]->{completed} }

package Zoidberg::Job::meta;

use strict;
use vars qw/$AUTOLOAD/;
use Zoidberg::Utils qw/:error/;

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
		zoid => $self->{zoid},
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

package Zoidberg::Contractor;

our $VERSION = '0.92';

use strict;
use POSIX ();
use Config;
use Zoidberg::Utils;
no warnings; # yes, undefined == '' == 0

=head1 NAME

Zoidberg::Contractor - Module to manage jobs

=head1 SYNOPSIS

	use Zoidberg::Contractor;
	my $c = Zoidberg::Contractor->new();
	
	$c->shell_list( [qw(cat ./log)], '|', [qw(grep -i error)] );

=head1 DESCRIPTION

Zoidberg inherits from this module, it manages jobs.

It uses Zoidberg::StringParser.

Also it defines Zoidberg::Job and subclasses.

FIXME lots of documentation

=head1 METHODS

=over 4

=item new()

Simple constructor, calls C<shell_init()>.

=cut

sub new { # stub, to be overloaded
	my $class = shift;
	shell_init(bless {@_}, $class);
}

=item shell_init()

Initialises things like hashes with signal names and sets terminal control.
Should be called before usage when the constructor is overloaded.

=cut

# Job control code adapted from example code 
# in the glibc manual <http://www.gnu.org/software/libc/manual>
# also some snippets from this manual include as comment blocks

# A subshell that runs non-interactively cannot and should not support job control.

sub shell_init {
	my $self = shift;
	bug 'Contractor can\'t live without a shell' unless $$self{shell};

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
			# FIXME is this logic allright !??
			CORE::kill($$self{_sighash}{TTIN}, -$self->{pgid}); # stop ourselfs
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

=item round_up()

Recursively calls the C<round_up()> function of all current jobs.

=cut

sub round_up { $_->round_up() for @{$_[0]->{jobs}} }

=item shell_list(@blocks)

Executes a list of jobs and logic operators.

=cut

sub shell_list {
	my ($self, @list) = grep {defined $_} @_;

	my $save_fg_job = $$self{shell}{fg_job}; # could be undef

	my $meta = (ref($list[0]) eq 'HASH') ? shift(@list) : {} ;
	return unless @list;

	my @re;
	PARSE_LIST:
	return unless @list;
	if (ref $list[0]) {
		eval {
			my $j = Zoidberg::Job->new(%$meta, boss => $self, tree => \@list);
			@list = @{$$j{tree}} and goto PARSE_LIST if $$j{empty};
			unless ( $$meta{prepare} ) { @re = $j->exec() }
			else {
				$j->bg(); # put it in @jobs
				$$j{bg} = 0;
			}
		};
		complain $@ if $@; # FIXME FIXME check eval {} blocks for redundancy
	}
	elsif (@{$$self{jobs}}) {
		debug 'enqueuing '.scalar(@list).' blocks';
		push @{$$self{jobs}[-1]{tree}}, @list;
	}
	else {
		debug 'no job to enqueu in, trying logic';
		@list = $self->_logic($$self{shell}{error}, @list);
		@re = $self->shell_list(@list);
	}

	$$self{shell}{fg_job} = $save_fg_job;

	return @re;
}

=item shell_job($block)

Executes a single job.

=cut

sub shell_job {
	my ($self, $meta, $block) = @_;
	$block = $meta unless ref($meta) eq 'HASH';
	my $save_fg_job = $$self{shell}{fg_job}; # could be undef
	my @re;
	eval {
		my $j = Zoidberg::Job->new(%$meta, boss => $self, procs => [$block]);
		@re = $j->exec()
	};
	complain $@ if $@;
	$$self{shell}{fg_job} = $save_fg_job;
	return @re;
}

=item reap_jobs()

Checks for jobs that are finished and removes them from the job list.

=cut

sub reap_jobs {
	my $self = shift;
	return unless  @{$self->{jobs}};
	my (@completed, @running);
	#debug 'reaping jobs';
	for ( @{$self->{jobs}} ) {
		next unless ref($_) =~ /Job/; # prohibit autogenerated faults
		$_->update_status;
		if ($_->completed) {
			if (@{$$_{tree}}) { $self->reinc_job($_) } # reincarnate it
			else { push @completed, $_ }
		}
		else { push @running, $_ }
	}
	$self->{jobs} = \@running;
	#debug 'body count: '.scalar(@completed);
	if ($$self{shell}{settings}{interactive}) {
		++$$_{completed} and message $_->status_string
			for sort {$$a{id} <=> $$b{id}} grep {! $$_{no_notify}} @completed;
	}
}

sub reinc_job { # reincarnate
	my ($self, $job) = @_;
	debug "job \%$$job{id} reincarnates";
	my @b = $self->_logic($$job{error}, @{$$job{tree}});
	return unless @b;
	$$job{tree} = [];
	debug @b. ' blocks left';
	$self->shell_list({ bg => $$job{bg}, id => $$job{id}, capture => $$job{capture} }, @b);
}

sub _logic {
	my ($self, $error, @list) = @_;
	my $op = ref( $list[0] ) ? 'EOS' : shift @list ;
	# mind that logic grouping for AND and OR isn't the same, OR is stronger
	while ( $error ? ( $op eq 'AND' ) : ( $op eq 'OR' ) ) { # skip
		my $i = 0;
		while ( ref $list[0] or $list[0] eq 'AND' ) {
			shift @list;
			$i++;
		}
		debug( ($error ? 'error' : 'no error') . " => $i blocks skipped" );
		$op = shift @list;
	}
	return @list;
}

# ############# #
# info routines #
# ############# #

=item job_by_id($id)

Returns a job object based on the (numeric) id.

(Note that the job list is un-ordered,
 so the id and the index are not usually identical.)
 
=item job_by_spec($string)

Returns a job object based on a string.
The following formats are supported:

=over 4

=item %I<integer>

Job with id I<integer>

=item %+

Current job

=item %-

Previous job

=item %?I<string>

Last job matching I<string>

=item %I<string>

Last job starting with I<string>

=back

=item sig_by_spec($string)

Returns the signal number for a named signal
or undef if no such signal exists.

=cut

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
	elsif ($q eq '+') { return $$self{jobs}[-1] if @{$$self{jobs}}     }
	elsif ($q eq '-') { return $$self{jobs}[-2] if @{$$self{jobs}} > 1 }
	elsif ($q eq '?') {
		for (reverse @{$$self{jobs}}) { return $_ if $$_{zoidcmd} =~ /$string/ }
	}
	else {
		for (reverse @{$$self{jobs}}) { return $_ if $$_{zoidcmd} =~ /^\W*$string/ }
	}
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
use vars '$AUTOLOAD';
use POSIX qw/:sys_wait_h :signal_h/;
use Zoidberg::Utils;

use overload
	'@{}' => sub { $_[0]->{tree} },
	fallback => 'TRUE';

our @ISA = qw/Zoidberg::Contractor/;

=back

=head1 JOBS

Jobs are objects of the class C<Zoidberg::Job> or a subclass of this class.

This object AUTOLOADS methods to process signals. For example:

  $job->TERM(); # is identical to
  $job->kill('TERM');

=head2 Methods

The job obbjects have the following methods:

=over 4

=item new()

Simple constructor.

=item exec()

Execute the job.

=item round_up()

Recursively kill the job, ends all child processes forcefully.

=cut

sub new { # @_ should at least contain 'boss' and either 'proc' or 'tree'
	shift; # class
	my $self = { new => 1, id => 0, procs => [], @_ };
	$$self{shell} ||= $$self{boss}{shell};
	$$self{$_}  ||= [] for qw/jobs tree/;
	$$self{$_} = $$self{boss}{$_} for qw/_sighash terminal/; # FIXME check this

	if ($$self{tree}) {
		while ( ref $$self{tree}[0] ) {
			my @b = grep {defined $_} $$self{shell}->parse_block(shift @{$$self{tree}});  # FIXME breaks interface, should be a hook
			if (@b > 1) { unshift @{$$self{tree}}, @b } # probably macro expansion
			else { push @{$$self{procs}}, @b }
		}
		$$self{bg}++ if $$self{tree}[0] eq 'EOS_BG';
	}

	return bless {%$self, empty => 1}, 'Zoidberg::Job' unless @{$$self{procs}};
	debug 'blocks in job ', $$self{procs};
	my $pipe = @{$$self{procs}} > 1;
	$$self{string}  ||= ($pipe ? '|' : '') . $$self{procs}[-1][0]{string};
	$$self{zoidcmd} ||= $$self{procs}[-1][0]{zoidcmd};

	my $meta = $$self{procs}[0][0];
	unless ($pipe || ( defined($$meta{fork_job}) ? $$meta{fork_job} : 0 ) || $$self{bg}) {
		bless $self, 'Zoidberg::Job::builtin'
	}
	else { bless $self, 'Zoidberg::Job' }

	return $self;
}

sub exec { 
	die unless ref($_[0]); # check against deprecated api
	my $self = shift;
	if (ref $_[0]) { %$self = (%$self, %{$_[0]}) }

	$$self{pwd} = $ENV{PWD};
	message $self->status_string('Running') if $$self{prepare};
	$$self{new} = 0;

	return unless @{$$self{procs}};
	local $ENV{ZOIDREF} = "$$self{shell}";

	my @re = eval { $self->_run };

	# bitmasks for return status of system commands
	# exit_value  = $? >> 8;
	# signal_num  = $? & 127; 
	# dumped_core = $? & 128;
	if ($@ || $$self{exit_status}) { # something went wrong
		my $error = ref($@) ? $@ : bless { string => ($@ || 'Error') }, 'Zoidberg::Utils::Error';
		if ($@) { complain }
		else { $$error{silent}++ }  # we trust processes returning an exit status to complain themselfs
		unless(defined $$error{exit_status}) { # maybe $@ allready contained one
			$$error{exit_status} = $$self{exit_status} >> 8; # only keep application specific bits
			my $signal = $$self{exit_status} & 127;
			$$error{signal} = $$self{_sighash}{$signal} if $signal;
			$$error{core_dump} = $$self{core_dump};
		}
		$error->PROPAGATE(); # just for the record
		$$self{error} = $$self{shell}{error} = $error;
	}
	else { delete $$self{shell}{error} }

	if ($self->completed()) {
		$$self{shell}->broadcast('envupdate'); # FIXME breaks interface
		$$self{boss}->reinc_job($self) if @{ $$self{tree} };
	}

	if ( $$self{tree}[0] eq 'EOS_BG' ) { # step over it - FIXME conflicts with fg_job
		shift @{$$self{tree}};
		my $ref = $$self{tree};
		$$self{tree} = [];
		$$self{boss}->shell_list(@$ref);
	}

	return @re;
}

sub round_up { 
	$_[0]->kill('HUP', 'WIPE');
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

sub _run {
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
			my $error = $@ || 0;
			if ($error) {
				complain;
				$error = ref($error) ? ($$error{exit_status} || 1) : 1 if $error;
			}
			exit $error; # exit child process
		}

		POSIX::close($stdin)  unless $stdin  == fileno STDIN ;
		POSIX::close($stdout) unless $stdout == fileno STDOUT;
		$stdin = $pipe[0] unless $$proc[0]{last} ;
	}

	my @re  = $$self{bg}      ? $self->bg
		: $$self{capture} ? ($self->_capture($stdin)) : $self->fg ;
 
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
	$self->wait_job; # job should be dead by now
	return @re;
}

sub _run_child { # called in child process
	my $self = shift;
	my ($block, $stdin, $stdout) = @_;

	$self->{shell}{round_up} = 0;
	$self->{shell}{settings}{interactive} = 0;
	map { $SIG{$_} = 'DEFAULT' } qw{INT QUIT TSTP TTIN TTOU};

	# make sure stdin and stdout are right, else dup them
	for ([$stdin, fileno STDIN], [$stdout, fileno STDOUT]) {
		next if $_->[0] == $_->[1];
		POSIX::dup2(@$_);
		POSIX::close($_->[0]);
	}

	$self->_set_env($block);

	# here we go ... finally
	$$self{shell}->eval_block($block); # FIXME should be hook
}

# ##################### #
# Execution environment #
# ##################### #

sub _set_env {
	my ($self, $block) = @_;

	# variables
	my @save_env;
	while (my ($env, $val) = each %{$$block[0]{env}}) {
		debug "env $env, val $val";
		push @save_env, [$env, $ENV{$env}];
		$ENV{$env} = $val;
	}
	return [\@save_env, []] unless $$block[0]{fd};

	# redirection
	my @save_fd;
	for my $fd (@{$$block[0]{fd}}) { # FIXME allow for IO objects
		my $newfd;
		$fd =~ m#^(\w*)(\W+)(.*)# or error "wrongly formatted redirection: $fd";
		my ($n, $op, $f) = ($1, $2, $3);
		$n ||= ($op =~ />/) ? 1 : 0;
		if ($op =~ /&=?$/) { # our dupping logic differs from open()
			if (! $f) { $newfd = 1 }
			elsif ($f =~ /^\d+$/) { $newfd = $f }
			else {
				no strict 'refs';
				my $class = $$self{shell}{settings}{perl}{namespace}
					|| 'Zoidberg::Eval';
				$newfd = fileno *{$class.'::'.$f};
				error $f.': no such filehandle' unless $newfd;
			}
		}
		else {
			error 'redirection needs argument' unless $f;
			error $f.': cannot overwrite existing file'
					if $op eq '>' 
					and $$self{shell}{settings}{noclobber}
					and -e $f;
			$op = '>' if $op eq '>!';
			debug "redirecting fd $n to $op$f";
			my $fh; # undefined scalar => new anonymous filehandle on open()
			open($fh, $op.$f) || error "Failed to open $op$f";
			($f, $newfd) = ($fh, fileno $fh); # re-using $f to have object in outer scope
		}
		debug "dupping fd $newfd to $n";
		push @save_fd, [POSIX::dup($n), $n];
		POSIX::dup2($newfd, $n) || error "Failed to dup $newfd to $n";
	}

	return [\@save_env, \@save_fd];
}

sub _restore_env {
	my ($save_env, $save_fd) = @{ pop @_ };

	for (@$save_fd) {
		POSIX::dup2(@$_);
		POSIX::close($_->[0]);
	}

	$ENV{$$_[0]} = $$_[1] for @$save_env;
}

# ########### #
# Signal code #
# ########### #

=item fg()

Take terminal control and run this job in the foreground.

=item bg()

Run this job in the background.

=cut

sub fg {
	my $self = shift;

	if ($$self{new}) {
		unshift @_, $self;
		goto &exec;
	}

	message $self->status_string('Running') if $$self{bg};
	$$self{bg} = 0;

	@{$$self{boss}{jobs}} = grep {$_ ne $self} @{$$self{boss}{jobs}};
	$$self{shell}{fg_job} = $self;

	POSIX::tcsetpgrp($self->{shell}{terminal}, $self->{pgid})
		if $self->{shell}{settings}{interactive};

	if ($self->{stopped}) {
		CORE::kill(SIGCONT, -$self->{pgid});
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

	if ($self->completed()) {
		$$self{shell}->broadcast('envupdate'); # FIXME breaks interface
		$$self{boss}->reinc_job($self) if @{ $$self{tree} };
	}
}

sub bg {
	my $self = shift;
	$self->_register_bg;

	if ($self->{stopped}) {
		CORE::kill(SIGCONT => -$self->{pgid});
		$self->{stopped} = 0;
	}

	message $self->status_string;
}

sub _register_bg { # register oneself as a background job
	my $self = shift;

	unless ($$self{id}) {
		$$_{id} > $$self{id} and $$self{id} = $$_{id} for @{$$self{boss}{jobs}};
		$$self{id}++;
	}

	@{$$self{boss}{jobs}} = grep {$_ ne $self} @{$$self{boss}{jobs}};
	push @{$$self{boss}{jobs}}, $self;

	$self->{bg} = 1;
}

# FIXME wait code when not interactive

sub wait_job {
	my $self = shift;
	while ( ! $self->{stopped} && ! $self->completed ) {
		my $pid;
		until ($pid = waitpid(-$self->{pgid}, WUNTRACED|WNOHANG)) {
			$self->{shell}->broadcast('ipc_poll');
			select(undef, undef, undef, 0.001);
		}
		$self->_update_child($pid, $?);
	}
}

sub update_status {
	my $self = shift;
	return if $$self{new};
	while (my $pid = waitpid(-$self->{pgid}, WUNTRACED|WNOHANG)) {
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
		CORE::kill(SIGTERM => -$self->{pgid} ); # just to be sure
		debug "group $$self{pgid} has disappeared:($!)";
		$$_[0]{completed}++ for @{$self->{procs}};
	}
	else {
		my ($child) = grep {$$_[0]{pid} == $pid} @{$$self{procs}};
		bug "Don't know this pid: $pid" unless $child;
		$$child[0]{exit_status} = $status;
		if (WIFSTOPPED($status)) { # STOP TSTP TTIN TTOUT
			$$self{stopped} = 1;
			if ( ! $$self{bg} and (
				WSTOPSIG($status) == SIGTTIN or
				WSTOPSIG($status) == SIGTTOU
			) )  { $self->fg           } # FIXME not sure why but this proves nescessary
			else { $self->_register_bg }
		}
		else {
			$$child[0]{completed} = 1;
			if ($pid == $$self{procs}[-1][0]{pid}) { # the end of the line ..
				$$self{exit_status} = $status;
				$$self{terminated}++ if $status & 127; # was terminated by a signal
				$$self{core_dump}++  if $status & 128;
				unless ($self->completed) { # kill the pipeline
					local $SIG{PIPE} = 'IGNORE'; # just to be sure
					$self->kill(SIGPIPE);
				}
			}
		}
	}
}

# TODO
# don't set shell exitstatus etc. if bg !
# run condition between the clean up and the kill for non interactive mode ?
# job seems not to get reaped whille stopped - should be continued at kill

# ###### #
# OO api #
# ###### #

=item kill($signal, $wipe_list)

Sends $signal (numeric or named) to all child processes belonging to this job;
$signal defaults to SIGTERM.

If the boolean $wipe_list is set all jobs pending in the same logic list are
removed.

=cut

sub kill {
	my ($self, $sig_s, $kill_tree) = @_;
	my $sig = defined($sig_s) ? $$self{shell}->sig_by_spec($sig_s) : SIGTERM;
	error "$sig_s: no such signal" unless $sig;
	@{$$self{tree}} = () if $kill_tree;
	if ($self->{shell}{settings}{interactive}) {
		CORE::kill( $sig => -$$self{pgid} );
	}
	else {
		CORE::kill( $sig => $_ )
			for map { $$_[0]{pid} } @{$$self{procs}};
	}
	$self->update_status();
}

=item env(\%env)

Set local environment for the current job.
Can't be set after the job has started.

=item fd(\@redir)

Set redirections for the current job.
Can't be set after the job has started.

=cut

sub env {
	my $self = shift;
	my $env = ref($_[0]) ? shift : { @_ };
	error "to late to set env, job is already running" unless $$self{new};
	for (@{$$self{procs}}) {
		$$_[0]{env} = $$_[0]{env} ? { %{$$_[0]{env}}, %$env } : $env;
	}
}

sub fd {
	my $self = shift;
	my $fd = ref($_[0]) ? shift : [ @_ ];
	error "to late to set fd, job is already running" unless $$self{new};
	for (@$fd) {
		my $block = /^[0<]/ ? $$self{procs}[0] : $$self{procs}[-1]; # in- or output
		$$block[0]{fd} ||= [];
		push @{$$block[0]{fd}}, $_;
	}
}

sub AUTOLOAD { # autoload signals - bo args
	my $self = shift;
	$AUTOLOAD =~ s/.*:://;
	$self->kill($AUTOLOAD);
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

	my $status = shift || (
		$$self{new}        ? 'New'         :
		$$self{stopped}    ? 'Stopped'     :
		$$self{core_dump}  ? 'Core dumped' :
		$$self{terminated} ? 'Terminated'  :
		$$self{completed}  ? 'Done'        : 'Running' ) ;

	my $string = $$self{string};
	$string =~ s/\n$//;
	$string .= "\t\t(pwd: $$self{pwd})" if $$self{pwd} and $$self{pwd} ne $ENV{PWD};

	return $pref . $status . "\t$string";
}

package Zoidberg::Job::builtin;

use strict;
use Zoidberg::Utils;

our @ISA = qw/Zoidberg::Job/;

sub round_up { $_->round_up() for @{$_[0]->{jobs}} }

sub _run { # TODO something about capturing :(
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

	my $save_capt;
	if ($$self{capture}) {
		debug "trying to capture a builtin";
		$save_capt = $$self{shell}{_builtin_output};
		$$self{shell}{_builtin_output} = [];
	}
	my $save_env = $self->_set_env($block);

	# here we go !
	eval { $$self{shell}->eval_block($block) };
		# FIXME should be hook
       		# VUNZig om hier een eval te moeten gebruiken

	$self->_restore_env($save_env);
	my @re;
	if ($$self{capture}) {
		@re = @{ $$self{shell}{_builtin_output} };
		$$self{shell}{_builtin_output} = $save_capt;
	}

	# restore other stuff
	$SIG{INT} = $saveint;
	$self->{completed}++;
	
	die if $@;

	return @re;
}

sub kill { error q#Can't kill a builtin# }
sub bg { error q#Can't put builtin in the background# }
sub fg { error q#Can't put builtin in the foreground# }

sub completed { $_[0]->{completed} }

1;

__END__

=back

=head1 AUTHORS

Jaap Karssenberg, E<lt>pardus@cpan.orgE<gt>

Raoul Zwart, E<lt>rlzwart@cpan.orgE<gt>

Copyright 2003 by Jaap Karssenberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<zoiddevel>(1),
L<Zoidberg>, L<Zoidberg::StringParser>

=cut

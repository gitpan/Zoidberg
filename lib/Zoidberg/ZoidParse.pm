package Zoidberg::ZoidParse;

our $VERSION = '0.3b';

use strict;
use POSIX ();
use Config;
use Zoidberg::Config;
use Zoidberg::Eval;
use Zoidberg::Error;
use Zoidberg::StringParse;
use Zoidberg::FileRoutines qw/is_exec_in_path/;

our $DEBUG = 0;
use Data::Dumper; # for debug only

sub init {
	my $self = shift;

	#### parser stuff ####
	$self->{_pending} = [];
	my $coll = Zoidberg::Config::readfile( $ZoidConf{grammar_file} );
	error "Bad grammar file: $ZoidConf{grammar_file}, missing word_gram or script_gram"
		unless exists($coll->{word_gram}) && exists($coll->{script_gram});
	$self->{StringParser} = Zoidberg::StringParse->new($coll->{_base_gram}, $coll);

	#### context stuff ####
	my %context;
	tie %context, 'Zoidberg::DispatchTable', $self, {
		_block_resolv => '->_block_context',
		_words_resolv => '->_words_context',
	};
	$self->{contexts} = \%context; # bindings for context routines
	$self->{_block_contexts} = []; # order for contexts, type block
	$self->{_words_contexts} = []; #        *idem*     , type words

	#### Command stuff ####
	my %comm;
	tie %comm, 'Zoidberg::DispatchTable', $self, {
		fg        => '->fg',
		bg        => '->bg',
		kill      => '->kill',
		jobs      => '->jobs',
		reload    => '->reload', # FIXME cross over with Zoidberg.pm
		exit      => '->exit',   #   *idem*
	};
	$self->{commands} = \%comm; # bindings for commands

	#### Alias stuff ####
	$self->{aliases} = { 'ls' => 'ls --color=auto' }; 
		# FIXME just testing - tie class to enable regexes etc ?

    #### jobs stuff ####
    $self->{jobs} = [];
    $self->{_sighash} = {};
    $self->{terminal} = fileno(STDIN);
    
    my @sno = split/[, ]/,$Config{sig_num};
    my @sna = split/[, ]/,$Config{sig_name};
    
    for my $i (0..$#sno) {
        $self->{_sighash}{$sno[$i]} = $sna[$i];
    }
    if ($self->{interactive}) {
        # /* Loop until we are in the foreground.  */
        while (POSIX::tcgetpgrp($self->{terminal}) != ($self->{pgid} = getpgrp)) {
            kill (21,-$self->{pgid}); # SIGTTIN , no constants to prevent namespace pollution
        }
        # /* ignore interactive and job control signals */
        map { $SIG{$_} = 'IGNORE'} qw{INT QUIT TSTP TTIN TTOU};
        # /* Put ourselves in our own process group.  */
        $self->{pgid} = $$;
        POSIX::setpgid($self->{pgid}, $self->{pgid});
        POSIX::tcsetpgrp($self->{terminal}, $self->{pgid});
        $self->{tmodes} = POSIX::Termios->new;
        $self->{tmodes}->getattr;
    }

	#### setup eval namespace ####
	$self->{_eval} = Zoidberg::Eval->_new($self);
}

sub round_up {
    my $self = shift;
    map {
        kill(1,-$_->{pgid}) # SIGHUP
    } grep {!$_->nohup} grep {ref =~ /Wide/} @{$self->{jobs}};
}

# ############### #
# Parser routines #
# ############### #

sub do {
	my $self = shift; 
	$self->update_status;
	my @list = eval { $self->parse(@_) };
	if ($@) {
		# FIXME broadcast event
		$self->print_error($@);
	}
	else { $self->do_list(\@list, 'PARSED') }
}

sub parse {
	my $self = shift;
	my @tree = $self->{StringParser}->split('script_gram', @_);
	if (my $e = $self->{StringParser}->error) { error $e }
	print 'tree1: ', Dumper \@tree if $DEBUG;
        my @tree = grep {defined $_} map { ref($_) ? $self->_resolv_context($$_) : $_} @tree;
	print 'tree2: ', Dumper \@tree if $DEBUG;
        return @tree;
}

sub _resolv_context  { # mag schoner, doch werkt 
	# args: string, broken_bit (also known as "Intel bit")
	my ($self, $string, $bit) = @_;

	# check block contexts
	my ($ref, %files);
	for ( @{$self->{_block_contexts}}, '_block' ) {
		next unless exists $self->{contexts}{lc($_).'_resolv'};
		$ref = $self->{contexts}{lc($_).'_resolv'}->($string, $bit);
		last if $ref;
	}

	# check word contexts
	unless ($ref) {
		my @words = $self->_split_words($string, $bit);
		return [{context => '_WORDS'}, @words] if $bit && $#words < 1;
		if (($#words > 1) && $words[-2] =~ /^(\d?)(>>|>|<)$/) { # parse redirections
			# FIXME what about escapes ? (see posix spec)
			my $num = $1 || ($2 eq '<') ? 0 : 1;
			$files{$num} = [pop(@words), $2];
			pop @words;
		}
		for ('_words', @{$self->{_words_contexts}}) {
			# FIXME hier net als bij intel gewoon _list sub gebruiken
			next unless exists $self->{contexts}{lc($_).'_resolv'};
			$ref = $self->{contexts}{lc($_).'_resolv'}->(\@words, $bit);
			last if $ref;
		}
		unless ($ref) {
			return undef if $bit || $string !~ /\S/;
			$ref = [ {context => 'sh'}, @words ]; # hardcoded default
		}
	}
	$ref = _expand_meta($ref);
	$ref->[0]{string} = $string;
	$ref->[0]{files}  = \%files;

	return $ref;
}

our $_perl_regexp = join '|', qw/
	if unless
	for foreach
	while until
	print
/; # FIXME make this configgable and add more words

sub _block_context {
	my ($self, $block, $bit) = @_;
	my $meta = {};
	if (
		$block =~ s/^\s*(\w*){(.*)}(\w*)\s*$/$2/s 
		|| ( $bit && $block =~ s/^\s*(\w*){(.*)$/$2/s )
	) {
		$meta->{context} = uc($1) || 'PERL';
		$meta->{opts} = $3;
		if (lc($1) eq 'zoid') {
			$meta->{context} = 'PERL';
			$meta->{dezoidify} = 1;
		}
		elsif (grep {$meta->{context} eq uc($_)} qw/sh cmd/, @{$self->{_words_contexts}}) {
			my @words = $self->_split_words($block, $bit);
			return [{context => '_WORDS'}, @words] if $bit && $#words < 1;
			return [$meta, @words];
		}
		else { return [$meta, $block] }
	}
	elsif ( $block =~ /^\s*(->|[\$\@\%\&\*\xA3]\S|($_perl_regexp)\b)/s ) {
		$meta->{context} = 'PERL';
		$meta->{dezoidify} = 1;
		return [$meta, $block];
	}
	else { return undef }
}

sub _words_context {
	my ($self, $block, $bit) = @_;
	my $meta = { _is_checked => 1 };
	# FIXME cross overs with Zoidberg class below :(
	if (exists $self->{commands}{$block->[0]} ) { 
		$meta->{context} = 'CMD';
		return [$meta, @$block];
	}
	elsif (
		($block->[0] =~ m|/| and -x $block->[0] and ! -d $block->[0])
		|| is_exec_in_path($block->[0])
	) {
		$meta->{context} = 'SH';
		return [$meta, @$block];
	}
	else { return undef }
}

sub _split_words {
	my ($self, $string, $broken) = @_;
	my @words = grep {$_} $self->{StringParser}->split('word_gram', $string);
	unless ($broken) { @words = $self->__do_aliases(@words) }
	else { push @words, '' if (! @words) || ($string =~ /(\s+)$/ and $words[-1] !~ /$1$/) }
	return @words; # filter out empty fields
}

sub __do_aliases {
	my ($self, $key, @rest) = @_;
	if (exists $self->{aliases}{$key}) {
		my $alias = $self->{aliases}{$key};
		@rest = $self->__do_aliases(@rest)
			if $alias =~ /\s$/; # recurs - see posix spec
		unshift @rest, 
			($alias =~ /\s/)
			? ( grep {$_} $self->{StringParser}->split('word_gram', $alias) )
			: ( $alias );
		return @rest;
	}
	else { return ($key, @rest) }
}

sub do_list {
	my ($self, $ref, $bit) = @_; # bit tells meta allready expanded
	my $prev_sign = '';
	while (scalar @{$ref}) {
		my ($pipe, $sign) = $self->_next_statement($ref);

		if ( defined($self->{exec_error}) ? ($prev_sign eq 'AND') : ($prev_sign eq 'OR') ) {
			$prev_sign = $sign if $sign =~ /^(EOS|BGS)$/;
			next;
		}
		else {
			$prev_sign = $sign;
			my $meta = {
				foreground => ($sign ne 'BGS'),
				string => (ref($pipe->[0][0]) eq 'HASH') 
					? $pipe->[0][0]{string} 
					: q{FIXME job description}, # VUNZIG
			};
			$pipe = [ map {_expand_meta($_) } @$pipe ] unless $bit;
			$self->do_job($meta, $pipe);
		}
	}
}

sub _next_statement {
	my ($self, $ref) = @_;
	my @r;
	return undef unless scalar(@{$ref});
	while ( scalar(@{$ref}) && ref($ref->[0]) ) { push @r, shift @{$ref} }
	my $sign = scalar(@{$ref}) ? shift @{$ref} : '' ;
	return \@r, $sign;
}

sub _expand_meta {
	my $block = shift;
	my $t = ref $block->[0];
	return $block if $t eq 'HASH';
	unless ($t) { $block->[0] = { context => $block->[0] } }
	elsif ($t eq 'ARRAY') {
		my ($cont, @opts) = @{$block->[0]};
		$block->[0] = {context => $cont, opts => \@opts};
	}
	else { die qq/Hands above the blankets !/ }
	return $block;
}

sub do_job {
	my $self = shift;
	my $job = Zoidberg::ZoidParse::scuddle->new($self, @_);
	push @{$self->{jobs}}, $job;
	eval { $job->run };
	if ($@) {
                $self->{exec_error} = $@;
                $self->print_error($@);
        }
        else { undef $self->{exec_error} }
	return $job->{id};
}

sub list_commands { keys %{$_[0]->{commands}} }

# ############ #
# Job routines #
# ############ #

sub jobs {
	my $self = shift;
	map { 
        my $s = $_->{string};
        chomp($s); if (!$_->{foreground}and!$_->{stopped}) { $s .= ' &' }
		$self->print("[$_->{id}] $s");
	}  grep {ref!~/native/i} @{$self->{jobs}};
}

sub fg {
    my $self = shift;
    my $id = shift;
    my $J;
    foreach my $job (@{$self->{jobs}}) {
        if (ref($job)!~/wide/i) { next }
        if ($id ) {
            if ($job->{id} == $id) { $J = $job; last }
            else { next }
        }
        if ((!$job->{fg})or$job->{stopped}) {
            $J = $job; last;
        }
    }
    if ($J) {
        $J->put_foreground;
    }
    else {
        $self->print("No such job",'error');
    }
}

sub bg {
    my $self = shift;
    my $id = shift;
    my $J;
    foreach my $job (@{$self->{jobs}}) {
        if (ref($job)!~/wide/i) { next }
        if ($id ) {
            if ($job->{id} == $id) { $J = $job; last }
            else { next }
        }
        if ((!$job->{fg})or$job->{stopped}) {
            $J = $job; last;
        }
    }
    if ($J) {
        $J->put_background;
    }
    else {
        $self->print("No such job",'error');
    }
}

sub kill {
    my $self = shift;
    my @a = $self->_substjobno(grep {!/^\s*$/} @_);
    if ($#a==-1) { error "Go kill yourself!" }
    elsif ($#a==0) { error "Kill $a[0] failed: $!" unless kill 9, $a[0] }
    else {
        my $sig;
        if ($sig = $self->_sigspec($a[0])) { shift @a }
        else { $sig = 9 } # SIGKILL .... again: ns polution
        for (@a) { error "Kill $_ failed: $!" unless kill 9, $_ }
    }
    # arg precedence als in bash..
}

sub disown { # dissociate job ... remove from @jobs, nohup
    my $self = shift;
    my $id = shift;
    unless ($id) { 
        my @jobs = grep {(!$_->{foreground})||($_->{stopped})} grep {ref =~ /Wide/} @{$self->{jobs}};
        if ($#jobs==-1) { error "No background job!" }
        elsif ($#jobs==0) { $id = $jobs[0]->{id} }
        else { error "Which job?" }
    }
    my ($job) = $self->_jobbyid($id);
    unless ($job) { error "No such job: $id" }
    todo 'see bash manpage for implementaion details';
    
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
    my $self = shift;
    my $id = shift;
    $id or return;
    [grep {$_->{id}==$id} @{$self->{jobs}}]->[0];
}

sub _fg_job {
    my $self = shift;
    grep { $_->{foreground} } grep {ref =~ /Wide/} @{$self->{jobs}};
}

sub _bg_job {
    my $self = shift;
    grep { (!$_->{foreground})||$_->{stopped} } grep { ref =~ /Wide/} @{$self->{jbos}};
}

sub _nextjobid {
    my $self = shift;
    my $h = [sort { $a <=> $b } map { $_->{id} } grep { ref =~ /Wide/i } @{$self->{jobs}}]->[-1] || 0;
    return $h+1;
}

sub reap_jobs {
    my $self = shift;
    eval { @{$self->{jobs}} = grep { !$_->completed } @{$self->{jobs}} };
    if ($@) {
        bug("very funky job control bug");
    }
}

sub update_status {
    my $self = shift;
    map {$_->update_status} @{$self->{jobs}};
    $self->reap_jobs;
}

sub _substjobno {
    my $self = shift;
    my @nus;
    for (@_) {
        if (/^\%(\d+)$/) {
            my$j=$self->_jobbyid($1);
            unless($j){$self->print("No such job: $1",'warning');next}
            push @nus, -$j->{pgid};
        }
        else {
            push @nus, $_;
        }
    }
    return @nus;
}
        
            
package Zoidberg::ZoidParse::scuddle;

use strict;
use IO::File;
use POSIX qw/:sys_wait_h :signal_h/;
use Zoidberg::Error;

sub new {
	my $class = shift;
	my $self = {
		zoid => shift,
		id => 0,
		files => { 0=>0, 1=>1, 2=>2 },
		tmodes => POSIX::Termios->new,
	};
	my $meta = shift;
	%{$self} = ( %{$self}, %{$meta} );
	$self->{tree} = shift;

	bless $self, $class;
	$self->classify;
}

sub zoid { $_[0]->{zoid} }

sub classify {
	my $self = shift;
    
	if ( # FIXME vunzige code
    		( scalar(@{$self->{tree}}) == 1 ) &&
		( $self->{tree}[0][0]{context} ne 'SH' or !$self->zoid->{round_up} ) &&
		$self->{foreground}
	) {
		$self->{block} = shift @{$self->{tree}};
		bless $self => 'Zoidberg::ZoidParse::scuddle::native'
	}
	else {
	    	bless $self => 'Zoidberg::ZoidParse::scuddle::wide';
	}
	$self->{id} = $self->zoid->_nextjobid;
    
	$self->zoid->print("Scuddle class ".ref($self)." in use.", "debug");
	return $self;
}

sub nohup { 0 }

sub do_redirect {
	my $block = pop;
	my @save_fd;
	for my $fd (keys %{$block->[0]{files}}) {
		my @opt = @{$block->[0]{files}{$fd}};
#		print STDERR "debug: going to redirect fd $fd to $opt[1]$opt[0]\n";
		my $fh = IO::File->new(@opt) || error "Failed to open $opt[1]$opt[0]";
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

package Zoidberg::ZoidParse::scuddle::native;

use strict;
use base 'Zoidberg::ZoidParse::scuddle';

sub run {
    my $self = shift;

	# prepare some stuff
	$self->{save_interactive} = $self->zoid->{interactive};
	$self->{saveint} = $SIG{INT};
	my $ii = 0;
	$SIG{INT} = sub {
		if (++$ii < 3) {
			$self->zoid->print("[$self->{id}] instruction terminated by SIGINT", 'message')
		}
		else { die "Got SIGINT 3 times, killing native scuddle\n" }
	};

	# do redirections
	my $save_fd = $self->do_redirect($self->{block});

	# here we go !
	eval { $self->zoid->{_eval}->_eval_block($self->{block}) }; # VUNZig om hier een eval te moeten gebruiken
	die if $@; 

	# restore file descriptors
	$self->undo_redirect($save_fd);

	# restore other stuff
	$self->zoid->{interactive} = $self->{save_interactive};
	$SIG{INT} = delete $self->{saveint};
	$self->{completed} = 1;
}

sub completed { $_[0]->{completed} }

sub stopped { 0 }

sub update_status { }

package Zoidberg::ZoidParse::scuddle::wide;

use strict;
use base 'Zoidberg::ZoidParse::scuddle';
use POSIX qw/:sys_wait_h :signal_h/;
use Zoidberg::Error;

sub run {
	my $self = shift;
	my $foreground = $self->{foreground};

	$self->{procs} = [ map {block => $_, completed => 0, stopped => 0}, @{$self->{tree}} ];
	$self->{procs}[-1]{last}++;
	my ($pid, @pipe, $stdin, $stdout);
	$stdin = fileno STDIN;
	for my $proc (@{$self->{procs}}) {
		unless ($proc->{last}) {
			@pipe = POSIX::pipe;
			$stdout = $pipe[1];
		}
		else { $stdout = fileno STDOUT }

		$pid = fork; # fork process
		if ($pid) { # parent process
			$proc->{pid} = $pid;
			if ($self->zoid->{interactive}) {
				$self->{pgid} ||= $pid ;
				POSIX::setpgid($pid, $self->{pgid});
			}
		}
		else { # child process
			$self->{zoid}{round_up} = 0;
			$self->run_child($proc, $stdin, $stdout, $foreground);
			exit 0; # exit child process
		}

		POSIX::close($stdin)  unless $stdin  == fileno STDIN ;
		POSIX::close($stdout) unless $stdout == fileno STDOUT;
		$stdin = $pipe[0] unless $proc->{last} ;
	}

	if ($foreground) { $self->put_foreground(0) }
	else { $self->put_background(0) }

	# postrun
	POSIX::tcsetpgrp($self->zoid->{terminal},$self->zoid->{pgid});
	error {silent => 1}, $self->{exit_status} if $self->{exit_status};
}

sub run_child {
	my $self = shift;
	my ($proc, $stdin, $stdout, $foreground) = @_;

	if ($self->zoid->{interactive}) {
		$self->{pgid} ||= $$;
		POSIX::setpgid(0,$self->{pgid});
		POSIX::tcsetpgrp($self->zoid->{terminal}, $self->{pgid}) if $foreground;
		map { $SIG{$_} = 'DEFAULT' } qw{INT QUIT TSTP TTIN TTOU CHLD};
	}

	# make sure stdin and stdout are right
	for ([$stdin, fileno STDIN], [$stdout, fileno STDOUT]) {
		next if $_->[0] == $_->[1];
		POSIX::dup2(@$_);
		POSIX::close($_->[0]);
	}

	# do redirections
	$self->do_redirect($proc->{block});

	$self->zoid->{interactive} = 0 unless -t STDOUT;
    	$self->zoid->silent;

	# here we go ... finally
	$self->zoid->{_eval}->_eval_block($proc->{block});
}

sub nohup {
    my $self = shift;
    $self->{nohup} = shift if @_;
    return $self->{nohup};
}

sub _wait_job {
    my $self = shift;
    my @a = @_;
    my $pid = undef;
    while (!$pid) {
        $pid = waitpid($a[0],$a[1]);
        $self->zoid->broadcast_event('poll_socket');
    }
    return $pid;
}

sub wait_job {
    my $self = shift;
    my ($status,$pid);
    do {
        $pid = $self->_wait_job(-$self->{pgid},WUNTRACED|WNOHANG);
        $status = $?;
        $self->{exit_status} = $status;
        $self->zoid->broadcast_event('idle');
    } while ($self->mark_process_status($pid,$status)&&!$self->stopped&&!$self->completed);
}

sub stopped {
    my $self = shift;
    $self->{stopped};
}

sub completed {
    my $self = shift;
    for (@{$self->{procs}}) {
        $_->{completed} || return 0;
    }
    return 1;
}

sub update_status {
    my $self = shift;
    my ($pid);
    do {
        $pid = waitpid(-1,WUNTRACED|WNOHANG);
        $self->zoid->broadcast_event('idle');
    } while $self->mark_process_status($pid,$?);
}

sub mark_process_status {
    my $self = shift;
    my ($pid,$status) = @_;
    foreach my $job (@{$self->zoid->{jobs}}) {
        for (@{$job->{procs}}) {
            $pid == $_->{pid} || next;
            $_->{status} = $status;
            if (WIFSTOPPED($status)) {
                $self->{stopped} = 1;
                if ((WSTOPSIG($status)==22)||(WSTOPSIG($status)==21)) { $job->put_foreground(1) } # funky
                else { $self->zoid->print("[$job->{id}] stopped by SIG".$self->zoid->{_sighash}{WSTOPSIG($status)},'message') }
                return 1;
            }
            $_->{completed} = 1;
            if (WIFSIGNALED($status)) {
                $self->zoid->print("[$job->{id}] terminated by SIG".$self->zoid->{_sighash}{WTERMSIG($status)},'message');
            }
            return 1;
        }
    }
    if ($pid>0) { $self->zoid->print("Unknown child process: $pid",'warning') }
    0;
}
        
sub put_foreground {
    my $self = shift;
    my $sig = shift;
    $self->{foreground} = 1;
    POSIX::tcsetpgrp($self->zoid->{terminal},$self->{pgid});
    if ($sig||$self->stopped) {
        #$self->{tmodes}->setattr($self->trog->shell_terminal,POSIX::TCSADRAIN);
        kill (SIGCONT,-$self->{pgid});
    }
    $self->wait_job;
    $self->{tmodes}->getattr;
    POSIX::tcsetpgrp($self->zoid->{terminal},$self->zoid->{pgid});
    #$self->zoid->{tmodes}->setattr($self->zoid->{terminal},POSIX::TCSADRAIN);
}

sub put_background {
    my $self = shift;
    my $cont = shift;
    $self->{foreground} = 0;
    if ($cont||$self->stopped) {
        kill (SIGCONT,-$self->{pgid});
    }
}

=cut

sub stdin {
    my $self = shift;
    $_=$self->{fd}{0};
    defined||return 0;
    ref($_) =~ /IO/ && return $_->fileno;
    $_;
}

sub stdout {
    my $self = shift;
    $_=$self->{fd}{1};
    defined||return 1;
    ref($_) =~ /IO/ && return $_->fileno;
    $_;
}

sub stderr {
    my $self = shift;
    $_=$self->{fd}{2};
    defined||return 2;
    ref($_) =~ /IO/ && return $_->fileno;
    $_;
}
=cut

1
__END__

=head1 NAME

Zoidberg::ZoidParse - Execute and/or eval statements

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

This module is not intended for external use ... yet.
Zoidberg inherits from this module, it the 
handles parsing and executing of command input.

It uses Zoidberg::StringParse and Zoidberg::Eval.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::StringParse>, L<Zoidberg::Eval>

=head1 AUTHORS

Jaap Karssenberg, E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Raoul Zwart, E<lt>carl0s@users.sourceforge.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Jaap Karssenberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

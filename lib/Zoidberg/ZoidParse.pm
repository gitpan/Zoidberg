package Zoidberg::ZoidParse;

our $VERSION = '0.3a_pre1';

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

sub do {
	my $self = shift; 
	eval { $self->do_list( [ $self->parse(@_) ] ) };
	$self->print_error($@) if $@;
}

sub parse {
	my $self = shift;
        my @tree = map { ref($_) ? $self->_resolv_context($$_) : $_} 
		$self->{StringParser}->split('script_gram', @_);
	error $self->{StringParser}->error if $self->{StringParser}->error;
	print 'tree: ', Dumper \@tree if $DEBUG;
        return @tree;
}

sub _resolv_context  { 
	# args: block, broken_bit
	my ($self, $block, $bit) = @_;
	my $ref;
	for ( @{$self->{_block_contexts}}, '_block' ) {
		next unless exists $self->{contexts}{lc($_).'_resolv'};
		$ref = $self->{contexts}{lc($_).'_resolv'}->($block, $bit);
		last if $ref;
	}
	unless ($ref) {
		my @words = $self->{StringParser}->split('word_gram', $block);
		@words = $self->_check_aliases(@words);
		@words = grep {$_} @words; # filter out empty fields
		for ('_words', @{$self->{_words_contexts}}) {
			next unless exists $self->{contexts}{lc($_).'_resolv'};
			$ref = $self->{contexts}{lc($_).'_resolv'}->(\@words, $bit);
			last if $ref;
		}
		unless ($ref || $bit) {# we're gonna die
			if ($words[0] =~ m|/|) {
				error $words[0].': No such file or directory' unless -e $words[0];
				error $words[0].': is a directory' if -d $words[0];
				error $words[0].': Permission denied'; 
			}
			else { error $words[0].': command not found' }
		}
		return undef unless $ref;
	}
	$ref->[0] = { context => $ref->[0] } unless ref $ref->[0];
	# NO array support here
	$ref->[0]->{string} = $block; 

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
	my $meta = { wrap => \&_block_context_wrap };
	if (
		$block =~ /^\s*(\w*){(.*)}(\w*)\s*$/s 
		|| ( $bit && $block =~ /^\s*(\w*){(.*)/s )
	) {
		$meta->{context} = $1 || 'PERL';
		$meta->{opts} = $3;
		return [$meta, $block];
	}
	elsif ( $block =~ /^\s*(->|[\$\@\%\&\*\xA3]\S|($_perl_regexp)\b)/s ) {
		$meta->{context} = 'PERL';
		return [$meta, $block];
	}
	else { return undef }
}

sub _block_context_wrap {
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

sub _check_aliases { # in which package does this belong ?
	my ($self, $key, @rest) = @_;
	if (exists $self->{aliases}{$key}) {
		$key = $self->{aliases}{$key};
		@rest = $self->_check_aliases(@rest) 
			if $key =~ /\s$/; # recurs - see posix spec
		unshift @rest, $self->{StringParser}->split('word_gram', $key);
		return @rest;
	}
	else { return ($key, @rest) }
}

sub do_list {
	my ($self, $ref) = @_;
	my $prev_sign = '';
	while (scalar @{$ref}) {
		my ($pipe, $sign) = $self->_next_statement($ref);

		if ( $self->{exec_error} ? ($prev_sign eq 'AND') : ($prev_sign eq 'OR') ) {
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

sub do_job {
	my $self = shift;
	#use Data::Dumper;
	#print 'do_job got: ', Dumper \@_;
	my $job = Zoidberg::ZoidParse::scuddle->new($self, @_);
	push @{$self->{jobs}}, $job;
	$job->prerun;
	$job->run;
	$job->postrun;
	return $job->{id};
}

sub list_commands { keys %{$_[0]->{commands}} }

# ############ #
# Job routines #
# ############ #

sub jobs {
	my $self = shift;
	map { 
		$self->print("[$_->{id}] $_->{string} ".($_->{foreground} ? " &" : ""))
	}  grep {ref!~/native/i} @{$self->{jobs}};
}

sub fg {
    my $self = shift;
    my $id = shift;
    unless ($id) { 
        my @jobs = grep {(!$_->{foreground})||($_->{stopped})} grep {ref =~ /Wide/} @{$self->{jobs}};
        if ($#jobs==-1) {
            $self->print("No background job!",'error');
            $self->{exec_error}=1;
            return;
        }
        elsif ($#jobs==0) {
            $id = $jobs[0]->{id};
        }
        else {
            $self->print("Which job?",'error');
            $self->{exec_error}=1;
            return;
        }
    }
    my ($job) = $self->_jobbyid($id);
    unless ($job) { $self->print("No such job: $id");$self->{exec_error}=1;return }
    $job->put_foreground;
}

sub kill {
    my $self = shift;
    my @a = $self->_substjobno(grep{!/^\s*$/}@_);
    if ($#a==-1) { $self->print("Go kill yourself!",'error');$self->{exec_error}=1;return }
    elsif ($#a==0) { unless(kill(9,$a[0])){$self->print("Kill $a[0] failed: $!",'error');$self->{exec_error}=1}}
    else {
        my $sig;
        if ($sig=$self->_sigspec($a[0])) { shift@a }
        else { $sig = 9 } # SIGKILL .... again: ns polution
        map {
            unless(kill(9,$_)){$self->{exec_error}=1}
        } @a;
    }
    # arg precedence als in bash..
}

sub bg {
    my $self = shift;
    my $id = shift;
    unless ($id) {
        my ($job) = $self->_fg_job;
        if ($job) {
            $id = $job->{id};
        }
        else {
            $self->print("No foreground job!",'error');
            $self->{exec_error} = 1;
            return;
        }
    }
    my ($job) = $self->_jobbyid($id);
    unless ($job) { 
        $self->print("No such job: $id",'error');
        $self->{exec_error} = 1;
        return;
    }
    $job->put_background;
}

sub disown { # dissociate job ... remove from @jobs, nohup
    my $self = shift;
    my $id = shift;
    unless ($id) { 
        my @jobs = grep {(!$_->{foreground})||($_->{stopped})} grep {ref =~ /Wide/} @{$self->{jobs}};
        if ($#jobs==-1) {
            $self->print("No background job!",'error');
            $self->{exec_error}=1;
            return;
        }
        elsif ($#jobs==0) {
            $id = $jobs[0]->{id};
        }
        else {
            $self->print("Which job?",'error');
            $self->{exec_error}=1;
            return;
        }
    }
    my ($job) = $self->_jobbyid($id);
    unless ($job) {
        $self->print("No such job: $id",'error');
        $self->{exec_error} = 1;
        return;
    }
    $self->print("Not yet implemented, please fill in the blanks at ".__FILE__." line ".__LINE__.".",'error');
    
    # see bash manpage for implementaion details
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
    my $h = [sort { $a <=> $b } map { $_->{id} } grep { ref =~ /Wide/ } @{$self->{jobs}}]->[-1] || 0;
    return $h+1;
}

sub reap_jobs {
    my $self = shift;
    @{$self->{jobs}} = grep { !$_->completed } @{$self->{jobs}};
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

use Data::Dumper;
use POSIX qw/:sys_wait_h :signal_h/;

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
	map { # support for multitype meta field
		my $t = ref $_->[0];
		unless ($t eq 'HASH') {
			unless ($t) { $_->[0] = { context => $_->[0] } }
			elsif ($t eq 'ARRAY') {
				my @a = @{$_->[0]};
				$_->[0] = {
					context => shift @a,
					opts => @a,
				}
			}
			else { die qq/Hands above the blankets !/ }
		}
	} @{$self->{tree}};

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
	) { bless $self => 'Zoidberg::ZoidParse::scuddle::native' }
	else { 
	    	bless $self => 'Zoidberg::ZoidParse::scuddle::wide';
		$self->{id} = $self->zoid->_nextjobid;
	}
    
	$self->zoid->print("Scuddle class ".ref($self)." in use.", "debug");
	return $self;
}

=begin comment

FIXME redirections are broken

ouwe method om redirections te vinde :

sub preparse {
    my $job = shift;
    ref($job) !~ 'scuddle' && $job->zoid->print("Gegegegeget a job [$job]", 'error');
    for my $i (0..$#{$job->{tree}}) {
        if ($job->{tree}[$i][1] =~ /</) {
            my $file = splice(@{$job->{tree}},$i+1,1);
            ($job->{tree}[$i][1],$file->[1])=($file->[1],$job->{tree}[$i][1]);
            $job->{files}{0} = $file;
        }
        if ($job->{tree}[$i][1] =~ />/) {
            my $file = splice(@{$job->{tree}},$i+1,1);
            ($job->{tree}[$i][1],$file->[1])=($file->[1],$job->{tree}[$i][1]);
            $job->{files}{1} = $file;
        }
    }
}

=end comment

=cut

sub nohup { 0 }

package Zoidberg::ZoidParse::scuddle::native;
use base 'Zoidberg::ZoidParse::scuddle';

sub prerun { # only stdout redirection supported for now ...
    my $self = shift;
    $self->{saveint} = $SIG{INT};
    $self->{save_interactive} = $self->zoid->{interactive};
    my $ii = 0;
    $SIG{INT} = sub{ # what does this _do_ !?
    	$ii++;
	if ($ii < 5) { $self->zoid->print("[$self->{id}] instruction terminated by SIGINT", 'message') }
	else { die "Got SIGINT 5 times, killing native scuddle\n" }
    };
    for (keys %{$self->{files}}) {
        if (ref($self->{files}{$_})) {
            my $file = $self->{files}{$_}[0];
            my $fh = IO::File->new("$self->{files}{$_}[1] $file");
            push @{$self->{files}{$_}}, select($fh);
            $self->zoid->{interactive} = 0;
        }
    }
}

sub run {
    my $self = shift;
    return $self->zoid->{_eval}->_eval_block($self->{tree}[0]);
}

sub postrun {
    my $self = shift;
    for (keys %{$self->{files}}) {
        if (ref($self->{files}{$_}) && $_ == 1 ) {
            select( pop( @{$self->{files}{$_}} ) );
        }
    }
    $self->zoid->{interactive} = $self->{save_interactive};
    $SIG{INT} = delete $self->{saveint};
    $self->{completed} = 1;
}

sub completed { $_[0]->{completed} }

sub stopped { 0 }

sub update_status { }

package Zoidberg::ZoidParse::scuddle::wide;
use base 'Zoidberg::ZoidParse::scuddle';

use Data::Dumper;
use POSIX qw/:sys_wait_h :signal_h/;

sub prerun {
    my $self = shift;
    my $foreground = $self->{foreground};
    $self->{fd} = { 
	map {
		$_, 
		ref($self->{files}{$_})
			? IO::File->new("$self->{files}{$_}[1]$self->{files}{$_}[0]")
			: $self->{files}{$_}
				? $self->{files}{$_}
				: $_
	}  keys %{$self->{files}} };
    my ($pid, @pipe, $infile, $outfile);
    $infile = $self->stdin;
    $self->{procs} = [];
    my $tree = $self->{tree};
    for my $i (0..$#{$tree}) {
        $self->{procs}[$i] = { 
		tak => $tree->[$i],
		completed => 0,
		stopped => 0
	};
        my $p = $self->{procs}[$i];
        if (defined $tree->[$i+1]) {
            @pipe=POSIX::pipe;
            $outfile = $pipe[1];
        }
        else {
            $outfile = $self->stdout;
        }
	
        $pid = fork; # !attention! FORK happens here
        if ($pid) { # parent process
           $p->{pid} = $pid;
           if ($self->zoid->{interactive}) {
               $self->pgid($pid) unless $self->pgid;
               POSIX::setpgid($pid, $self->pgid);
           }
        }
        else { # child process
            $self->{zoid}{round_up} = 0;
            $self->launch($p, $infile, $outfile, $self->stderr, $foreground);
        }

        if ($infile != $self->stdin) {
            POSIX::close($infile);
        }
        if ($outfile != $self->stdout) {
            POSIX::close($outfile);
        }
        $infile = $pipe[0];
    }
    if ($foreground) {
        $self->put_foreground(0);
    }
    else {
        $self->put_background(0);
    }
}

sub pgid {
    my $self = shift;
    if (@_) {
        $self->{pgid} = shift;
    }
    $self->{pgid};
}

sub nohup {
    my $self = shift;
    if (@_) {
        $self->{nohup} = shift;
    }
    $self->{nohup};
}

sub run {
    my $self = shift;
}

sub launch {
    my $self = shift;
    my ($p, $stdin, $stdout, $stderr, $foreground) = @_;
    my ($pid);
    if ($self->zoid->{interactive}) {
        $pid = $$;
        unless ($self->{pgid}) { $self->pgid($pid) }
        POSIX::setpgid(0,$self->{pgid});
        if ($foreground) {
            POSIX::tcsetpgrp($self->zoid->{terminal},$self->{pgid});
        }
        map { $SIG{$_} = 'DEFAULT' } qw{INT QUIT TSTP TTIN TTOU CHLD};
    }
    if ($stdin != fileno(STDIN)) {
        POSIX::dup2($stdin,fileno(STDIN));
        POSIX::close $stdin;
    }
    if ($stdout != fileno(STDOUT)) {
        POSIX::dup2($stdout,fileno(STDOUT));
        POSIX::close $stdout;
    }
    if ($stderr != fileno(STDERR)) {
        POSIX::dup2($stderr,fileno(STDERR));
        POSIX::close $stderr;
    }
    unless (-t STDOUT) { $self->zoid->{interactive} = 0 }
    $self->zoid->silent;
    $self->zoid->{_eval}->_eval_block($p->{tak});
    exit 0;
}

sub wait_job {
    my $self = shift;
    my ($status,$pid);
    do {
        $pid = waitpid(-$self->{pgid},WUNTRACED);
        $status = $?;
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
                $self->zoid->{exec_error} = 1;
            }
            elsif ($status) {
                $self->zoid->{exec_error} = 1;
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

sub postrun {
    my $self = shift;
    POSIX::tcsetpgrp($self->zoid->{terminal},$self->zoid->{pgid});
}

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

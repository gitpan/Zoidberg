package Zoidberg::ZoidParse;

##Insert version Zoidberg here##

use POSIX ();
use Config;
use Zoidberg::Eval;

# ################ #
# Public interface #
# ################ #

sub trog {
    my $self = shift;
    $self->update_status;
    $self->{exec_error} = 0;
    my @pending = map {@{$self->{StringParser}->parse($_,'script_gram')}} grep { length } (@_);
    $self->{StringParser}{error} &&
        ($self->print($self->{StringParser}{error},'error'),return "");
    my $prev_sign = '';
    my $return = '';
    for (@pending) {
        my ($string,$sign,$context) = @{$_}; #print "debug <$string,$sign,$context>\n";

        if ($self->{exec_error} ?
            (grep {$prev_sign =~ /^$_$/} @{$self->{grammar}{logic_and}}) :
            (grep {$prev_sign =~ /^$_$/} @{$self->{grammar}{logic_or}})
        ) {
            if (grep {$sign =~ /^$_$/} @{$self->{grammar}{end_of_statement}}) { $prev_sign = $sign }
            next;
        }
        else {
            $self->{exec_error} = 0;
            $prev_sign = $sign;
            if (($string=~/^\s$/)||!length($string)) { next } # filthy, i know ... but it works for now, just don't speak bleach natively
            my $tree = $self->{StringParser}->parse($string, 'pipe_gram');
            $self->{StringParser}{error} &&
                ($self->print("Error swallowing content: $self->{StringParser}{error}", 'error'),$self->{exec_error}=1);
            $return = $self->scuddle($tree,$string,$sign);
        }
    }
    $self->update_status;
    return $return;
}

sub _init_posix { # init all kinds of weird posix shit ... and also Zoidberg::Eval
    my $self = shift;
    $self->{terminal} = fileno(STDIN);
    $self->{jobs} = [];
    $self->{_sighash} = {};
    my @sno=split/[, ]/,$Config{sig_num};
    my @sna=split/[, ]/,$Config{sig_name};
    for (my$i=0;$i<=$#sno;$i++) {
        $self->{_sighash}{$sno[$i]}=$sna[$i];
    }
    if ($self->{interactive}) {
        # /* Loop until we are in the foreground.  */
        while (POSIX::tcgetpgrp($self->{terminal}) != ($self->{pgid} = getpgrp)) {
            kill (21,-$self->{pgid}); # SIGTTIN , no constants to prevent namespace pollution
        }
        # /* ignore interactive and job control signals */
        map {$SIG{$_}='IGNORE'} qw{INT QUIT TSTP TTIN TTOU};
        # /* Put ourselves in our own process group.  */
        $self->{pgid} = $$;
        POSIX::setpgid($self->{pgid},$self->{pgid});
        POSIX::tcsetpgrp($self->{terminal},$self->{pgid});
        $self->{tmodes} = POSIX::Termios->new;
        $self->{tmodes}->getattr;
    }

    $self->{_Eval} = Zoidberg::Eval->_New($self);
}

sub _round_up_posix {
    my $self = shift;
    map {
        kill(1,-$_->{pgid}) # SIGHUP
    } grep {!$_->nohup} grep {ref =~ /Wide/} @{$self->{jobs}};
}

sub jobs {
    my $self = shift;
    map { if ($_->{foreground}) { $b=" &" } else { $b="" } $a="[$_->{id}] $_->{string} $b"; $self->print($a);$a}  grep {ref!~/native/i} @{$self->{jobs}};
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
    $self->print("Not yet implemented, please fill in the blanks at ".__FILE__." line ".__LINE__.".",'warning');
    
    # see bash manpage for implementaion details
    # does thhis suggest we could also have a 'own' to hijack processes ?
    # all your pty are belong:0
}

=pod
## I believe this to be deprecated
sub _scuddle_cmd {
    my $self = shift;
    my $string = shift;
    my $context = shift;
    my $job = Scuddle->new($self,[ [$string, '', $context, ''] ],0);
    push @{$self->{jobs}}, $job;
    $job->{string} = $string;
    my @pipe = POSIX::pipe;
    $job->{files}{1} = $pipe[1];
    $job->preparse;
    $job->{id} = $self->_nextjobid;
    $job->prerun;
    $job->postrun;
    my $fh = IO::File->new_from_fd($pipe[0],'r');
    #$fh->blocking(0);
    my @dus = (<$fh>);
    $fh->close;
    return @dus;
}
=cut

# ################## #
# Internal interface #
# ################## #

sub scuddle {
    my $self = shift;
    my ($tree, $string, $sign)  = @_;
    my $fg;
    if (grep {$sign =~ /^$_$/} @{$self->{grammar}{background}}) { $fg = 0 } else { $fg = 1 }
    my $job = Scuddle->new($self,$tree,$fg);
    push @{$self->{jobs}}, $job;
    $job->{string} = $string;
    $job->preparse;
    if (ref($job)=~/Wide/) { $job->{id} = $self->_nextjobid }
    else { $job->{id} = 0 }
    $job->prerun;
    my $return = $job->run;
    $job->postrun;
    return $return;
}

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
        
            
package Scuddle;

use Data::Dumper;
use POSIX qw/:sys_wait_h :signal_h/;
use Zoidberg::FileRoutines qw/is_executable/;

sub new {
    my $cls = shift;
    my $self = {
        zoid => shift,
        tree => shift,
        foreground => shift,
        files => {0=>0,1=>1,2=>2},
        tmodes => POSIX::Termios->new,
    };
    bless $self => $cls;
    $self->preparse;
    $self->classify;
}

sub zoid { $_[0]->{zoid} }

sub classify {
    my $self = shift;
    if (($#{$self->{tree}}==0)&&($self->{tree}[0][2]ne'SYSTEM'or!$self->zoid->{round_up})&&$self->{foreground}) {bless $self => 'Scuddle::Native'; }
    #if (($#{$self->{tree}}==0)&&$self->{foreground}) { bless $self => 'Scuddle::Native'; }
    else { bless $self => 'Scuddle::Wide'; }
    $self->zoid->print("Scuddle class ".ref($self)." in use.", "debug");
    return $self;
}

sub preparse {
    my $job = shift;
    ref($job) !~ 'Scuddle' && $job->zoid->print("Gegegegeget a job [$job]", 'error');
    for (my $i=0;$i<=$#{$job->{tree}};$i++) {
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

sub nohup { 0 }

package Scuddle::Native;
use base 'Scuddle';

sub prerun { # only stdout redirection supported for now ...
    my $self = shift;
    $self->{saveint} = $SIG{INT};
    $self->{save_interactive} = $self->zoid->{interactive};
    my $ii=0;
    $SIG{INT}=sub{$ii++;if($ii<5){$self->zoid->print("[$self->{id}] instruction terminated by SIGINT", 'message')}else{die"Got SIGINT 5 times, killing native scuddle"}};
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
    return $self->zoid->{_Eval}->_Eval_block($self->{tree}[0][0], @{$self->{tree}[0]}[2..3]);
}

sub postrun {
    my $self = shift;
    for (keys %{$self->{files}}) {
        if (ref($self->{files}{$_})&&$_==1) {
            select(pop(@{$self->{files}{$_}}));
        }
    }
    $self->zoid->{interactive} = $self->{save_interactive};
    $SIG{INT} = delete $self->{saveint};
    $self->{completed} = 1;
}

sub completed { $_[0]->{completed} }

sub stopped { 0 }

sub update_status { }

package Scuddle::Wide;
use base 'Scuddle';

use Data::Dumper;
use POSIX qw/:sys_wait_h :signal_h/;

sub prerun {
    my $self = shift;
    my $foreground = $self->{foreground};
    $self->{fd} = { map {$_, ref($self->{files}{$_})?IO::File->new("$self->{files}{$_}[1]$self->{files}{$_}[0]"):$self->{files}{$_}?$self->{files}{$_}:$_ }  keys %{$self->{files}} }; 
    my ($pid,@pipe,$infile,$outfile);
    $infile = $self->stdin;
    $self->{procs} = [];
    my $tree = $self->{tree};
    for (my$i=0;$i<=$#{$tree};$i++) {
        $self->{procs}[$i]={tak=>$tree->[$i],completed=>0,stopped=>0};
        my $p = $self->{procs}[$i];
        if (defined $tree->[$i+1]) {
            @pipe=POSIX::pipe;
            $outfile = $pipe[1];
        }
        else {
            $outfile = $self->stdout;
        }
        $pid = fork;
        if ($pid) {
           $p->{pid} = $pid;
           if ($self->zoid->{interactive}) {
               unless ($self->pgid) {
                   $self->pgid($pid);
               }
               POSIX::setpgid($pid,$self->pgid);
           }
        }
        else {
            $self->{zoid}{round_up} = 0;
            $self->launch($p,$infile,$outfile,$self->stderr,$foreground);
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
    my ($p,$stdin,$stdout,$stderr,$foreground) = @_;
    my ($pid);
    if ($self->zoid->{interactive}) {
        $pid = $$;
        unless ($self->{pgid}) { $self->pgid($pid) }
        POSIX::setpgid(0,$self->{pgid});
        if ($foreground) {
            POSIX::tcsetpgrp($self->zoid->{terminal},$pgid);
        }
        map {$SIG{$_}='DEFAULT'}qw{INT QUIT TSTP TTIN TTOU CHLD};
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
    unless (-t STDOUT) { $self->zoid->{interactive}=0 }
    $self->zoid->silent;
    my $ret = $self->zoid->{_Eval}->_Eval_block($p->{tak}[0],@{$p->{tak}}[2..3]);
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
        $_->{completed}||return 0;
    }1;
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
    ref($_)=~/IO/&&return $_->fileno;
    $_;
}

sub stdout {
    my $self = shift;
    $_=$self->{fd}{1};
    defined||return 1;
    ref($_)=~/IO/&&return $_->fileno;
    $_;
}

sub stderr {
    my $self = shift;
    $_=$self->{fd}{2};
    defined||return 2;
    ref($_)=~/IO/&&return $_->fileno;
    $_;
}

1
__END__

=head1 NAME

Zoidberg::ZoidParse - The execution backend ... aka trog

=head1 SYNOPSIS

  Again, this module is not intended for external use ... yet
  Zoidberg inherits from this module, hence the funky method names:0

=head1 ABSTRACT

  Perl blocks, unix commands, file handles... You name it, trog glues it together

=head1 DESCRIPTION

  anusbille

=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Raoul Zwart, E<lt>carl0s@users.sourceforge.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002 by root

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

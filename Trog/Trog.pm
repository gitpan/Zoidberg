package Zoidberg::Trog;

use POSIX qw{:sys_wait_h :signal_h :errno_h};
use base 'Zoidberg::Fish';

our $VERSION = 0.04;

our ($shell_pgid,$shell_tmodes,$shell_terminal,$shell_is_interactive);

sub init {
    my $self = shift;
    $self->{first_job} = undef;
    $self->init_shell;
}
 
sub init_shell {
    my $self = shift;
    $shell_terminal = fileno(STDIN);
    $shell_is_interactive = -t STDIN;
    if ($shell_is_interactive) {
        
        # /* Loop until we are in the foreground.  */
        while (POSIX::tcgetpgrp($shell_terminal) != ($shell_pgid = getpgrp)) {
            kill (- $shell_pgid, SIGTTIN);
        }
        
        # /* ignore interactive and job control signals */
        map {$SIG{$_}='IGNORE'} qw{INT QUIT TSTP TTIN TTOU CHLD};
        
        # /* Put ourselves in our own process group.  */
        $shell_pgid = $$;
        if (POSIX::setpgid($shell_pgid,$shell_pgid) < 0) {
           print STDERR "Couldn't put the shell in its own process group\n";
           exit 1;
        }
        
        # /* Grab control of the terminal.  */
        POSIX::tcsetpgrp($shell_terminal,$shell_pgid);
        
        # /* Save default terminal attributes for shell.  */
        # POSIX::tcgetattr($shell_terminal,$shell_tmodes);
        $shell_tmodes = POSIX::Termios->new;
        $shell_tmodes->getattr;
    }
}

sub parse { # todo: zoid->{exec_error} setten
    my $self = shift;
    my $tree = shift;
    unless ($tree->[0][0]) { $self->parent->{exec_error}++; return "" }
    my $job = Job->new($self);
    my @p;
    my $foreground = 1;
    for (my$i=0;$i<=$#{$tree};$i++) {
        my $process = {exec=>$tree->[$i][0],fd=>{},context=>$tree->[$i][2]};
        my $ni = $i+1;
        if ($tree->[$i][1]=~/</) {
            if ($tree->[$ni]) {
                $process->{fd}{0} = $tree->[$ni][0]->{string};
            }
            else {
                print "filename expected after `<'\n";
                $self->parent->{exec_error}++; return "";
            }
            splice(@{$tree},$ni,1)
        }
        elsif ($tree->[$i][1]=~/>/) {
            if ($tree->[$ni]) {
                $process->{fd}{1} = $tree->[$ni][0]->{string};
            }
            else {
                print "filename expoected after `<'\n";
                $self->parent->{exec_error}++; return "";
            }
            splice(@{$tree},$ni,1)
        }
        elsif ($tree->[$i][1]=~/&/) {
            $foreground--;
        }

        push @p, $process;
    }

    my $first = pop(@p);
    my $fp = Kiff->new($job,$first->{exec},$first->{context},$first->{fd});
    $first = $fp;
    for (reverse @p) {
        my $proc = Kiff->new($job,$_->{exec},$_->{context},$_->{fd});
        $proc->{next} = $first;
        $first = $proc;
    }
    
    $job->{first_process} = $first;
    $self->{first_job} = $job;
    $job->launch($foreground);
    $self->notify;
}
    
sub find_job {
    my $self = shift;
    my $pgid = shift;
    for(my$job=$self->{first_job};defined$job;$job=$job->{'next'}) {
        if ($job->{pgid}==$pgid) {
            return $job;
        }
    }
    return;
}

sub mark_process_status {
    my $self = shift;
    my $pid = shift;
    my $status = shift;
    # print "[$$]: \$pid: $pid, \$status: $status, \$?: $?\n";
    # print STDERR "mark_process_status($pid,$status)\n";
    if ($pid) {
        for (my$j=$self->{first_job};defined$j;$j=$j->{next}) {
            for (my$p=$j->{first_process};defined$p;$p=$p->{next}) {
                if ($p->{pid} == $pid) {
                    # print "pid: $pid, status: $status\n";
                    $p->{status} = $status;
                    if (WIFSTOPPED($status)) {
                        $p->{stopped} = 1;
                        return 1;
                    }
                    $p->{completed} = 1;
                    if (WIFSIGNALED ($status)) {
                        print "$pid terinated by signal ".WTERMSIG($status)."\n";
                        $self->parent->{exec_error} = 1;
                    }
                    elsif ($status) {
                        $self->parent->{exec_error} = 1;
                    }
                    return 1;
                }
            }
        }
    }
    
    elsif ($pid == 0||$?==ECHILD) {
        print "hoererererere\n";
        return -1;
    }
    elsif ($pid == -1) {
        $self->parent->{exec_error}=1;    
    }
    # print "[$$]: \$pid: $pid, \$status: $status, \$?: $?\n";
    return 0;
}

sub update_status {
    my $self = shift;
    my ($status,$pid);
    do {
        $pid = waitpid(-1,WUNTRACED|WNOHANG);
    } while mark_process_status($pid,$?);
}

sub notify {
    my $self = shift;
    my ($j,$jlast,$jnext,$p);
    $self->update_status;
    $jlast = undef;
    for($j=$self->{first_job};defined($j);$j=$j->{next}) {
        $jnext = $j->{next};
        if ($j->completed) {
            # print STDERR "job $j has completed\n";
            if ($jlast) {
                $jlast->{next} = $j->{next};
            }
            else {
                $self->{first_job} = $jnext;
            }
        }
        elsif ($j->stopped&&!$j->{notified}) {
            # print STDERR "job $j has stopped\n";
            $j->{notified} = 1;
            $jlast = $j;
        }
        else {
            $jlast = $j;
        }
    }
}
 
sub interactive { $shell_is_interactive }

sub shell_terminal { $shell_terminal }

sub tmodes { $shell_tmodes }

sub shell_pgid { $shell_pgid }

sub pgid { $shell_pgid }

package Job;

use POSIX qw{:signal_h sys_wait_h};
use IO::File;

sub new {
    my $class = shift;
    my $self = {};
    $self->{trog}=shift;
    $self->{first_process}=shift;
    $self->{notified} = 1;
    bless $self => $class;
}

sub stopped {
    my $self = shift;
    for (my$p=$self->{first_process};defined$p;$p=$p->{next}) {
        if (!$p->completed&&!$p->stopped) {
            return 0;
        }
    }
    return 1;
}

sub completed {
    my $self = shift;
    for (my$p=$self->{first_process};defined$p;$p=$p->{next}) {
        unless ($p->completed) {
            return 0;
        }
    }
    return 1;
}

sub continue {
    my $self = shift;
    my $foreground = shift;
    $self->mark_running;
    if ($foreground) {
        $self->put_foreground(1);
    }
    else {
        $self->put_background(1);
    }
}

sub launch {
    my $self = shift;
    my $foreground = shift;
    my $runstr;
    my ($pid,@pipe,$infile,$outfile);
    $infile = $self->stdin;
    for (my$p=$self->{first_process};defined$p;$p=$p->{next}) {
        if (defined $p->{next}) {
            @pipe=POSIX::pipe;
            $outfile = $pipe[1];
        }
        else {
            $outfile = $self->stdout;
        }
        
        $pid = fork;
        
        if ($pid) {
            $p->{pid} = $pid;
            $runstr .= "[$pid:$p->{cmd}],";
            if ($self->trog->interactive) {
                unless ($self->pgid) {
                    $self->{pgid} = $pid;
                }
                # print "job: [$pid,$self->{pgid}]\n"; # maybe the parent has to set it first?
                unless(setpgrp($pid,$self->{pgid})) { }#print "Job->setpgrp($pid,$self->{pgid}): $!\n"; }
            }
        }
        else {
            # dan hier maar ff die files doen ...
            if ($p->{fd}{0}) {
                my $fh = IO::File->new("$p->{fd}{0}") or die "$p->{fd}{0}: $!\n";
                $infile = $fh->fileno;
            }
            elsif ($p->{fd}{1}) {
                my $fh = IO::File->new(">$p->{fd}{1}") or die ">$p->{fd}{1}: $!\n";
                $outfile = $fh->fileno;
            }
                        
            $p->launch($self->pgid,$infile,$outfile,$self->stderr,$foreground);
        }

        # clean up after pipes ...
    
        if ($infile != $self->stdin) {
            POSIX::close($infile);
        }
        if ($outfile != $self->stdout) {
            POSIX::close($outfile);
        }
        $infile = $pipe[0];
    }

    if (!$self->trog->interactive) {
        $self->waitjob;
    }

    elsif ($foreground) {
        $self->put_foreground(0);
    }

    else {
        $self->put_background(0);
    }
    # $runstr =~ s{,$}{\n};
    # print STDERR $runstr;
}

sub put_foreground {
    my $self = shift;
    my $cont = shift;
    POSIX::tcsetpgrp($self->trog->shell_terminal,$self->{pgid});
    if ($cont) {
        $self->tmodes->setattr($self->trog->shell_terminal,POSIX::TCSADRAIN);
        kill (- $self->{pgid}, SIGCONT);
    }
    $self->wait_job;

    POSIX::tcsetpgrp($self->trog->shell_terminal,$self->trog->shell_pgid);
    $self->tmodes->getattr;
    $self->trog->tmodes->setattr($self->trog->shell_terminal,POSIX::TCSADRAIN);
}

sub put_background {
    my $self = shift;
    my $cont = shift;
    kill (- $self->{pgid},SIGCONT);
}

sub wait_job {
    my $self = shift;
    # print STDERR "[$$]: $self->wait_job\n";
    my ($status,$pid);
    do {
        $pid = waitpid(-1,WUNTRACED);
    } while ($self->trog->mark_process_status($pid,$?)&&!$self->stopped&&!$self->completed);
}
 
sub mark_running {
    my $self = shift;
    my $p;
    for ($p=$self->{first_process};defined$p;$p=$p->{next}) {
        $p->{stopped} = 0;
    }
    $self->{notified} = 0;
}
        
sub stdout { fileno(STDOUT) }
sub stdin { fileno(STDIN) }
sub stderr { fileno(STDERR) }
sub tmodes { $shell_tmodes }
sub trog { $_[0]->{trog} }
sub pgid { $_[0]->{pgid} }
 
package Kiff;

sub new {
    my $class = shift;
    my $self = {};
    $self->{job} = shift;
    $self->{cmd} = shift;
    $self->{context} = shift;
    #$self->notify;
    $self->{fd} = shift;
    bless $self => $class;
}

sub launch {
    my $self = shift;
    my ($pgid,$infile,$outfile,$errfile,$foreground) = @_;
    my $pid;
    if ($self->job->trog->interactive) {
        # /* Put the process into the process group and give the process group
        # the terminal, if appropriate.
        # This has to be done both by the shell and in the individual
        # child processes because of potential race conditions.  */
        
        $pid = $$;
        unless ($pgid) { $pgid = $pid;$self->job->{pgid} = $pid }
        $self->dump;
        # print "pid: $pid, pgid: $pgid\n";
        unless (setpgrp($pid,$pgid)) { }# print "Kiff->setpgrp($pid,$pgid): $!\n"; } # bsd ... AND POSIX ...
        $self->dump;
        
        if ($foreground) {
            POSIX::tcsetpgrp($self->job->trog->shell_terminal,$pgid);
        }
        
        map {$SIG{$_}='DEFAULT'}qw{INT QUIT TSTP TTIN TTOU CHLD};
    }
    
    # pijpe ...
    if ($infile != fileno(STDIN)) {
        POSIX::dup2($infile,fileno(STDIN));
        POSIX::close $infile;
    }
    if ($outfile != fileno(STDOUT)) {
        POSIX::dup2($outfile,fileno(STDOUT));
        POSIX::close $outfile;
    }
    if ($errfile != fileno(STDERR)) {
        POSIX::dup2($errfile,fileno(STDERR));
        POSIX::close $errfile;
    }
    
    exit $self->runnit;
}

sub sys {
    my $self = shift;
    my $parser = Zoidberg::StringParse->new($self->job->trog->parent->{grammar},'space_gram');
    exec(grep{length}map{$_->[0]} @{$parser->parse($self->{cmd})});
}

sub reval {
    my $self = shift;
    $self->{exec} =~ s/^\s*\{//;
    $self->{exec} =~ s/\{\s*$//;
    $self->job->trog->safe->reval($self->{exec});
}
    
sub runnit {
    my $self = shift;
    if ($self->{context} eq 'PERL') {
        $self->reval;
    }
    elsif ($self->{context} eq 'SYSTEM') {
        $self->sys;
    }
}

sub job { $_[0]->{job} }

sub dump {
    my $pgid = getpgrp;
    # print "[$$,$pgid]\n";
} 

sub completed { $_[0]->{completed} }

sub stopped { $_[0]->{stopped} }

package Process;

use base 'Kiff';
1;
__END__
package Main;
$|++;
my $t = Trog->new;
my $j = Job->new($t);
my $p = Kiff->new($j,'ls -al');
$p->{next} = Kiff->new($j,'tr e a');
$p->{next}{next} = Kiff->new($j,'tr j z');

$j->{first_process} = $p;
$t->{first_job} = $j;
$j->launch(1);

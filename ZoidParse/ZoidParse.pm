package Zoidberg::ZoidParse;

use POSIX ();

# ################ #
# Public interface #
# ################ #

sub trog {
    my $self = shift;
    $self->{exec_error} = 0;
    my @example = ('ls -la | tr e a > /tmp/dus && cat < /tmp/dus && cat /etc/services | {print map {y/a/e/} (<>)} >> dus && ->Buffer->monkey || ->fuckit');
    my @pending = map {@{$self->{StringParser}->parse($_,'script_gram')}} grep { length } (@_);
    $self->{StringParser}{error} &&
        ($self->print($self->{StringParser}{error},'error'),return "");
    my $prev_sign = '';
    my $return = '';

    for (@pending) {
        my ($string,$sign) = @{$_};

        if ($self->{exec_error} ?
            (grep {$prev_sign =~ /^$_$/} @{$self->{grammar}{logic_and}}) :
            (grep {$prev_sign =~ /^$_$/} @{$self->{grammar}{logic_or}})
        ) {
            if (grep {$sign =~ /^$/} @{$self->{grammar}{end_of_statement}}) { $prev_sign = $sign }
            next;
        }
        else {
            $self->{exec_error} = 0;
            $prev_sign = $sign;

            my $tree = $self->{StringParser}->parse($string, 'pipe_gram');
            $self->{StringParser}{error} &&
                ($self->print("Error swallowing content: $self->{StringParser}{error}", 'error'),$self->{exec_error}=1);
            my $id = [sort {$a <=> $b} map {$_->{id}} @{$self->{jobs}}]->[-1];
            my $job = Scuddle->new($self,$tree,$id||1);
            $job->preparse;
            $job->prerun;
            $return = $job->run;
            $job->postrun;
        }
    }
    return $return;
}

sub _init { # init all kinds of weird posix shit ...
    my $self = shift;
    $self->{terminal} = fileno(STDIN);
    if ($self->{interactive}) {
        # /* Loop until we are in the foreground.  */
        while (POSIX::tcgetpgrp($self->{terminal}) != ($self->{pgid} = getpgrp)) {
            kill (21,-$self->{pgid}); # SIGTTIN
        }
        # /* ignore interactive and job control signals */
        map {$SIG{$_}='IGNORE'} qw{INT QUIT TTIN TTOU CHLD};
        $SIG{TSTP}=sub{$self->sigbg($_[0])};
        # /* Put ourselves in our own process group.  */
        $self->{pgid} = $$;
        POSIX::setpgid($self->{pgid},$self->{pgid});
        POSIX::tcsetpgrp($self->{terminal},$self->{pgid});
        $self->{tmodes} = POSIX::Termios->new;
        $self->{tmodes}->getattr;
    }
}
 
sub sigbg {
    my $self = shift;
    $self->print("Put the current foreground job in the background",'message');
}

# ################## #
# Internal interface #
# ################## #


package Scuddle;

use Data::Dumper;
use POSIX qw/:sys_wait_h :signal_h/;

sub new {
    my $cls = shift;
    my $self = {
        zoid => shift,
        tree => shift,
        id => shift,
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
    if (($#{$self->{tree}}==0)&&($self->{tree}[0][2]ne'SYSTEM')) {
        bless $self => 'Scuddle::Native';
    }
    else {
        bless $self => 'Scuddle::Wide';
    }
    $self;
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

sub eval_block { # This was Zoidberg.pm's parse_block, env is already set up (forks, fhs) just run the damn thing
    my $self = shift;
    my ($string,$context,$options) = @_;
    $self->zoid->print(qq|Scuddle::eval_block($string, '$context')|,'debug');
    if (ref($self->zoid->{grammar}{context}{$context})&&$self->zoid->{grammar}{context}{$context}[0]) {
        my $sub = $self->zoid->{grammar}{context}{$context}[0];
        $string =~ s/'/\\'/g; # put safety escape on
        my @dus = ("'$string'");
        if ($sub =~ s/(\(.*\))\s*$//) {
            length($1) && push @dus, eval($1);
        }
        my $eval_string = 'sub { my $self = shift; $self->'.$sub.'('.join(', ', @dus).') }';
        $self->zoid->print(qq(going to eval "$eval_string"),'debug');
        my $re = [eval{eval($eval_string)->($self->zoid)}];
        if ($@) {
            $self->zoid->{exec_error} = $1;
            $self->zoid->print(qq(Your spinal fin seems to be missing: $@), 'error');
            return $re;
        }
    }
    elsif ($context eq 'PERL') {
        my $re = $self->eval_zoid($string,$options.'Z');
        $self->zoid->print("\n",'',1);
        return $re;
    }
    elsif ($context eq 'ZOID') { return $self->eval_zoid($string,$options) }
    elsif ($context eq 'SYSTEM') { return $self->eval_system($string,$options) }
    elsif ($context eq 'FILE') { return $self->eval_file($string,$options) }
}

sub eval_zoid {
    my $self = shift;
    my $eval_code_string = shift;
    my $block_options = shift;
    my $parse_tree = $self->zoid->{StringParser}->parse($eval_code_string,'eval_zoid_gram');
    my $m = $self->zoid->{grammar}{pound_sign};
    foreach my $ref (@{$parse_tree}) {
        if ($ref->[1] eq "${m}_") { $ref->[1] = '$self->{exec_topic}'}
        elsif ($ref->[1] =~ s/^(->|($m))//) {
            if ($self->zoid->{core}{show_naked_zoid} && ($1 ne $2)) { $ref->[1] = '$self->'.$ref->[1]; }
            elsif (grep {$_ eq $ref->[1]} @{$self->zoid->clothes}) { $ref->[1]='$self->'.$ref->[1]}
            elsif ($ref->[1] =~ m|^\{(\w+)\}$|) { $ref->[1] = '$self->{vars}'.$self->[1]}
            else { $ref->[1] = '$self->objects(\''.$ref->[1].'\')' }
        }
    }
    $eval_code_string = join('', map {$_->[0].$_->[1]} @{$parse_tree});
    if ($block_options =~ m/g/) { $eval_code_string = 'while (<STDIN>) { if (eval {'.$eval_code_string.'}) {print $_} }'; }
    elsif ($block_options =~ m/p/) { $eval_code_string = 'while (<STDIN>) {'.$eval_code_string.';print $_}'; }
    elsif ($block_options =~ m/n/) { $eval_code_string = 'while (<STDIN>) {'.$eval_code_string.'}'; }
    if (($block_options !~ m/z/) && ($block_options =~ m/Z/)) { $eval_code_string = 'no strict;'.$eval_code_string; }
    $eval_code_string = 'sub { my $self = shift; '.$eval_code_string." }";
    $self->zoid->print("going to eval: '$eval_code_string'", 'debug');
    $_ = $self->{zoid}{exec_topic};
    my $sub = eval($eval_code_string);
    my $ret = [eval{eval($eval_code_string)->($self->zoid)}];
    $self->{zoid}{exec_topic} = $_;
    if ($@) {
        $self->zoid->{exec_error} = 1;
        $self->zoid->print("bwuububububu buuuu: '$@'", 'error');
    }
    return $ret;
}

sub eval_system {
    my $self = shift;
    my $string = shift;
    my $ps = $self->zoid->{grammar}{pound_sign};
    $string =~ m/^\s*(.*?)\s*$/;
    my @args = map {$_->[0]} @{$self->zoid->{StringParser}->parse($1,'space_gram')};
    if ($self->zoid->is_executable($args[0]) ) {
        my $bin = shift @args;
        my @exp_args = ();
        for (@args) {
            s/${ps}_/$self->{zoid}{exec_topic}/g;
            if ($_ =~ /[^\w\s\\\/\.]/) { push @exp_args, @{$self->zoid->Intel->expand_files($_)} }
            else { push @exp_args, $_; }
        }
        @exp_args = map {s/\\//g; $_} @exp_args;
        $self->zoid->print("Going to system: ( \'$bin\', \'".join('\', \'', @exp_args)."\')", 'debug');
        exec($bin,@exp_args);
    }
    else {
        $self->zoid->print("No such executable: $args[0]", 'error');
        $self->{exec_error} = 1;
    }
}

package Scuddle::Native;
use base 'Scuddle';

sub prerun { # only stdout redirection supported for now ...
    my $self = shift;
    $self->{saveint} = $SIG{INT};
    $self->{save_interactive} = $self->zoid->{interactive};
    $SIG{INT}=sub{$self->sigint};
    for (keys %{$self->{files}}) {
        if (ref($self->{files}{$_})&&$_==1) {
            my $file = $self->{files}{$_}[0];
            my $fh = IO::File->new("$self->{files}{$_}[1] $file");
            push @{$self->{files}{$_}}, select($fh);
	        $self->zoid->{interactive} = 0;
        }
    }
}

sub sigint {
    my $self = shift;
    $self->zoid->print("[$self->{id}] instruction terminated by signal 2", 'message');
}

sub run {
    my $self = shift;
    return $self->eval_block($self->{tree}[0][0], @{$self->{tree}[0]}[2..3]);
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
}

package Scuddle::Wide;
use base 'Scuddle';

use Data::Dumper;
use POSIX qw/:sys_wait_h :signal_h/;

sub prerun {
    my $self = shift;
    my $foreground = 1;
    $self->{fd} = { map {$_, ref($self->{files}{$_})?IO::File->new("$self->{files}{$_}[1]$self->{files}{$_}[0]"):$_ }  keys %{$self->{files}} }; 
    my ($pid,@pipe,$infile,$outfile);
    $infile = $self->stdin;
    $self->{procs} = [];
    my $tree = $self->{tree};
    for (my$i=0;$i<=$#{$tree};$i++) {
        $self->{procs}[$i]={tak=>$tree->[$i]};
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
    if (!$self->zoid->{interactive}) {
        $self->wait_job;
    }
    elsif ($foreground) {
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

sub run {
    my $self = shift;
}

sub launch {
    my $self = shift;
    my ($p,$stdin,$stdout,$stderr,$foreground) = @_;
    my $pid;
    if ($self->zoid->{interactive}) {
        $pid = $$;
        unless ($pgid) { $pgid = $pid;$self->pgid($pgid) }
        POSIX::setpgid(0,$pgid);
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
    my $ret = $self->eval_block($p->{tak}[0],@{$p->{tak}}[2..3]);
    exit 0;
}

sub wait_job {
    my $self = shift;
    my ($status,$pid);
    do {
        $pid = waitpid(-1,WUNTRACED|WNOHANG);
        select(undef,undef,undef,0.01);
    } while ($self->mark_process_status($pid,$?)&&!$self->stopped&&!$self->completed);
}

sub stopped {
    my $self = shift;
    $self->{stopped};
}

sub completed {
    my $self = shift;
    $self->{completed};
}

sub update_status {
    my $self = shift;
    my ($pid);
    do {
        $pid = waitpid(-1,WUNTRACED|WNOHANG);
    } while mark_process_status($pid,$?);
}

sub mark_process_status {
    my $self = shift;
    my ($pid,$status) = @_;
    if ($pid) {
        for (my$i=0;$i<=$#{$self->{procs}};$i++) {
            my $p = $self->{procs}[$i];
            if ($p->{pid} == $pid) {
                $p->{status} = $status;
                if (WIFSTOPPED($status)) {
                    $self->zoid->print("$self->{id} stopped [$pid,$status]",'message');
                    $self->{stopped} = 1;
                    return 1;
                }
                $self->{completed} = 1;
                if (WIFSIGNALED ($status)) {
                    $self->zoid->print("$self->{id} signalled [$pid,".WTERMSIG($status)."]",'message');
                    $self->zoid->{exec_error} = 1;
                }
                elsif ($status) {
                    $self->zoid->{exec_error} = 1;
                }
                return 1;
            }
        }
    }
    elsif ($pid == 0||$?==ECHILD) {
        #print "very funky canonball race going on ...\n";
        #$self->zoid->{exec_error} = 1;
        $self->{completed} = 1;
        return 1;
    }
    elsif ($pid == -1) {
        $self->{completed} = 1;
        $self->zoid->{exec_error}=1;
    }
    return 0;
}


sub put_foreground {
    my $self = shift;
    my $sig = shift;
    $self->{foreground} = 1;
    POSIX::tcsetpgrp($self->zoid->{terminal},$self->{pgid});
    if ($sig) {
        $self->{tmodes}->setattr($self->trog->shell_terminal,POSIX::TCSADRAIN);
        kill (SIGCONT,-$self->{pgid});
    }
    $self->wait_job;
    POSIX::tcsetpgrp($self->zoid->{terminal},$self->zoid->{pgid});
    $self->{tmodes}->getattr;
    $self->zoid->{tmodes}->setattr($self->zoid->{terminal},POSIX::TCSADRAIN);
}

sub put_background {
    my $self = shift;
    my $cont = shift;
    $self->{foreground} = 0;
    if ($cont) {
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

1;
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

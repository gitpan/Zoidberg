#!/usr/bin/perl

package Exec;

use IO::Handle;
use POSIX;

sub new { bless {} => $_[0] }

sub in {
    my $self = shift;
    if (@_) {
        $self->{in} = shift;
    }
    else { return $self->{in} }
}

sub out {
    my $self = shift;
    if (@_) {
        $self->{out} = shift;
    }
    else { return $self->{out} }
}

sub preprun {
    my $self = shift;
    if ($self->in) {
        $self->in->reader;
        dup2($self->in->fileno,fileno(STDIN));
        $self->in->close;

    }
    if ($self->out) {
        $self->out->writer;
        dup2($self->out->fileno,fileno(STDOUT));
        $self->out->close;
    }
}

package Exec::Perl;

# TODO: 
#       shared, $self locken:)

use base 'Exec';

sub runFork {
    my $self = shift;
    unless (fork) {
        $self->preprun;
        $self->reval;
        exit;
    }
    else {
        return 1;
    }
}

sub run {
    my $self = shift;
    $self->runFork(@_);
    #$self->runThread(@_);
    # if ($Config{useithreads}) {
    #   $self->runThread;
    # }
    # else {
    #   $self->runFork;
    # }
}

sub runThread {
    use threads;
    my $self = shift;
    my $t = threads->new(sub{$self->preprun;$self->reval});
    $self->{thread} = $t;
    #$t->detach;
    return 1;
}
 
sub reval { while (<>) { y/e/a/;print } }

sub thread { $_[0]->{thread} }

package Exec::Perl::Sletjes;

use base 'Exec::Perl';

sub reval { print"billy is een slettebeffende meneereneukende hoereslet\n" }

package Exec::System;

use base 'Exec';

sub run {
    my $self = shift;
    my $pid = fork;
    if ($pid) {
        # parent ... 
        $self->{pid} = $pid;
        return 1;
    }
    else {
        $self->preprun;
        # child, dus je ding doen, i/o staan al in de (pijp)
        exec($self->cmd);
    }
}

sub cmd { qw{echo billy is een slettebeffende meneereneukende hoereslet} }

package Exec::System::Cat;

use base 'Exec::System';

sub cmd { qw{cat} }

package Main;

use IO::Pipe;

my @parsetree = qw/Exec::Perl::Sletjes Exec::System::Cat Exec::Perl/;
my @objs;
my $pipe;

while (@parsetree) {
    my $class = shift@parsetree;
    my $ding = $class->new;
    if ($pipe) {
        $ding->in($pipe);
    }
    if ($parsetree[0]) {
        $pipe = IO::Pipe->new;
        $ding->out($pipe);
    }
    push @objs, $ding;
}

map{$_->run}@objs;


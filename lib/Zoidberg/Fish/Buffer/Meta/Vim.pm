package Zoidberg::Fish::Buffer::Meta::Vim;

our $VERSION = '0.3b';

use strict;
use base 'Zoidberg::Fish::Buffer::Meta';

sub _do_key {
    my $self = shift;
    my $chr = shift;
    my $sub = 'default($chr)';

    my $cnt = 1;
    if ($self->_get_movement($chr)) { 
        my ($cmd) = grep {$self->{_meta_fb}=~/\Q$_\E/} keys %{$self->{bindings}{$self->{current_modus}}{vim_commands}};
        unless (grep {$self->{_meta_fb}=~/\Q$_\E/} keys %{$self->{bindings}{$self->{current_modus}}{vim_commands}}) {
            $self->{_meta_fb}=~m/^(-?\d*)$/;
            my $c = $1;
            if (length$c) { $cnt = $1 }
            $sub = $self->_get_movement($chr);
            $self->{_meta_fb} = '';
        }
        else {
            $self->{_meta_fb}=~m/^(-?\d*)\Q$cmd\E(-?\d*)$/;
            my ($c1,$c2) = ($1,$2);
            $self->{_meta_fb} = '';
            return $self->_do_vim_command($c1,$cmd,[$c2,$chr]);
        }
    }
    elsif ($self->{bindings}{$self->{current_modus}}{$chr}) {
        $sub = $self->{bindings}{$self->{current_modus}}{$chr};
        $self->{_meta_fb}=~m/^-?(\d*)$/;
        my $c = $1;
        if (length$c) { $cnt = $1 }
        $self->{_meta_fb} = '';
    }
    elsif ($self->{bindings}{_all}{$chr}) { $sub = $self->{bindings}{_all}{$chr};$self->{_meta_fb} = '' }
    elsif ($self->can('k_'.$chr)) { $sub = 'k_'.$chr; $self->{_meta_fb} = ''}

    $self->__do_sub($chr,$cnt,$sub);
}

sub default {
    my $self = shift;
    $self->{_meta_fb} .= shift;
}

sub __do_sub {
    my $self = shift;
    my $chr = shift;
    my $cnt = shift;
    my $sub = shift;
    my @opts = ();
    $sub =~ s/^->/parent->/;
    if ($sub =~ s/(\(.*\))\s*$//) { unshift @opts, eval($1); }
    my $e_sub = eval("sub { \$self->$sub(\@_) }");
    return map {$e_sub->(@opts,$cnt)} (1);
}
    
sub _get_movement {
    my $self = shift;
    my $chr = shift;
    $self->{bindings}{$self->{current_modus}}{movement}{$chr};
}

sub _do_vim_command {
    my $self = shift;
    my $cnt = shift;
    my $cmd = shift;
    my ($oc,$ok) = @{$_[0]};
    unless(length($oc)){$oc=1}
    unless(length($cnt)){$cnt=1}
    if ($ok eq 'd') {
        # hmmmm.....
    }
    my $sub = $self->_get_movement($ok);
    $self->switch_modus('select');
    Zoidberg::Buffer::Meta::Vim::__do_sub($self,$ok,$oc,$sub); # insert dd hack here:)
    my $command = $self->{bindings}{meta}{vim_commands}{$cmd};
    if (($command eq 'delete')||($command eq 'replace')) {
        $self->rub_out;
    }
    if ($command eq 'replace') {
        $self->switch_modus('insert');
    }
    else {
        $self->switch_modus('meta');
    }
}

1;


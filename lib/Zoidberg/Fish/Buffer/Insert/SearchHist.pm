package Zoidberg::Fish::Buffer::Insert::SearchHist;
use base 'Zoidberg::Fish::Buffer::Insert';

our $VERSION = '0.41';

use strict;

sub _switch_on {
    my $self = shift;
    $self->{custom_prompt} = 1;
    $self->{prompt} = q/Search history: '/.$self->{fb}[$self->{pos}[1]].q/' : /;
    $self->{prompt_lenght} = length($self->{prompt});
}

sub _switch_off { $_[0]->{custom_prompt} = 0 }

sub _do_key {
    my $self = shift;
    my $key = shift;
    if ($key eq 'return') {
        delete $self->{_searchres};
        $self->switch_modus;
        $self->_do_key('return'); #hehehehe
        return;
    }
    elsif ($key eq 'escape' or $key eq 'left' or $key eq 'right') {
        delete $self->{_searchres};
        $self->switch_modus;
        return;
    }
    $self->{_searchres} ||=[''];
    $self->{fb} = delete $self->{_searchres};
    $self->switch_modus;
    $self->_do_key($key);
    $self->switch_modus('search_hist');
    my $res = $self->parent->History->search($self->{fb}[$self->{pos}[1]]);
    $self->{_searchres} = $self->{fb};
    unless (defined $res) { $res = [''] }
    $self->{fb}=$res;
}

1;


package String;

use Term::ANSIColor();

sub new {
    my $class = shift;
    my $self = {parent=>shift,cont=>shift};
    $self->{lookup} = $self->{parent}{lookup};
    bless $self => $class;
    if (@_) {
        $self->color(shift);
    }
    return $self;
}

sub replaceVar {
    my $self = shift;
    my $var = shift;
    unless (exists $self->{lookup}{$var}) { return $var }
    if (ref($self->{lookup}{$var}) eq 'CODE') {
        return $self->{lookup}{$var}->($self);
    }
    else {
        return $self->{lookup}{$var};
    }
}

sub set {
    my $self = shift;
    $self->{cont} = shift;
}

sub isCode {
    my $self = shift;
    if (ref($self->{cont}) eq 'CODE') {
        return 1;
    }
    return 0;
}

sub get {
    my $self = shift;
    $self->{cont};
}

sub getLength {
    my $self = shift;
    return length(stripAnsi($self->{laststring}));
}

sub stripAnsi {
    my $string = shift;
    $string =~ s{\e.*?m}{}g;
    return $string;
}
            
sub color {
    my $self = shift;
    if (@_) {
        $self->{color} = shift;
    }
    else {
        return $self->{color};
    }
}

sub cont {
    my $self = shift;
    return $self->{cont};
}

sub stringify {
    my $self = shift;
    my $string;
    if ($self->isCode) { $string = $self->cont->($self) }
    elsif (!ref($self->cont)) { $string = $self->cont }
    $string = $self->expandVars($string);
    $string = $self->colorify($string);
    $self->{laststring} = $string;
    return $self->{laststring};
}

sub colorify {
    my $self = shift;
    my $string = shift;
    if ($self->color) {
        $string = Term::ANSIColor::color($self->color).$string.Term::ANSIColor::color('reset');
    }
    return $string;
}

sub expandVars {
    my $self = shift;
    my $string = shift;
    $string =~ s{(\\[a-z])}{$self->replaceVar($1)}gie;
    return $string;
}

package Zoidberg::Prompt;

use strict;
use base 'Zoidberg::Fish';

sub init {
	my $self = shift;
	$self->{parent} = shift;
	$self->{config} = shift;
    $self->{lookup} = $self->{parent}->pd_read($self->{config}{file});
    $self->{children} = [];
    $self->append($self->{config}{prompt});
}

sub children {
    my $self = shift;
    if (@_) { return $self->{children}[shift] }
    @{$self->{children}};
}

sub createChild {
    my $self = shift;
    return new String ($self,@_);
}

sub getLength {
    my $self = shift;
    my $tot;
    for ($self->children) {
        $tot+=$_->getLength;
    }
    $tot;
}

sub append {
    my $self = shift;
    $self->{children} = [];
    for (@_) {
        if (ref($_) eq 'ARRAY') {
            $self->append(@{$_});
        }
        elsif (ref($_) eq 'HASH') {
            my ($cont,$col) = each %{$_};
            my $child = $self->createChild($cont,$col);
            push @{$self->{children}},$child;
        }
        else {
            push @{$self->{children}},$self->createChild($_);
        }
    }
}

sub stringify {
    my $self = shift;
    my $str;
    for ($self->children) {
        $str .= $_->stringify;
    }
    return $str;
}

sub reset {
    my $self = shift;
    $self->{children} = [];
}

1;
__END__
=head1 NAME

Zoidberg::Prompt - Modular prompt plugin for Zoidberg

=head1 SYNOPSIS

    
  

=head1 DESCRIPTION

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>.

=cut

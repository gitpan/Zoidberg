package Zoidberg::Fish;

sub new {
    my $class = shift;
    my $self = {};
    bless $self => $class;
}

sub init {
    my $self = shift;
    $self->{parent} = shift;
    $self->{config} = shift;
    $self->register_events;
    $self->postinit;
    return 1;
}

sub postinit {
    my $self = shift;
}

sub round_up {
    my $self = shift;
    return 1;
}

sub parent {
    my $self = shift;
    return $self->{parent};
}

sub print {
    my $self = shift;
    $self->parent->print(@_);
}

sub config {
    my $self = shift;
    return $self->{config};
}

sub precmd {
    my $self = shift;
}

sub postcmd {
    my $self = shift;
}

sub register_event {
    my $self = shift;
    $self->parent->register_event($_[0],$self);
}

sub register_events {
    my $self = shift;
    for (qw/precmd/) {
        $self->register_event($_);
    }
}

sub registered_events {
    my $self = shift;
    return $self->parent->registered_events($self);
}

sub unregister_event {
    my $self = shift;
    my $event = shift;
    $self->parent->unregister_event($event);
}

sub unregister_events {
    my $self = shift;
    for ($self->registered_events) {
        $self->unregister_event($_);
    }
}

sub help {
	my $self = shift;
	return "This module does not (yet) have a detailed help text.";
}

1;
__END__

=head1 NAME

Zoidberg::Fish - Base class for loadable objects

=head1 SYNOPSIS

  package My::Dynamic::ZoidPlugin
  use base 'Zoidberg::Fish';
  

=head1 DESCRIPTION

  This should be the abstract for Zoidberg::Fish.
  Well what do you know ... it is!
  If you inherit from this class, you don't need to declare the init, round_up and new methods:)

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>.

=cut

package Zoidberg::Fish;

##Insert version Zoidberg here##

use Devel::Symdump;
use Zoidberg::Fish::Crab;

sub new {
    my $class = shift;
    my $self = {};
    $self->{parent} = shift;
    $self->{config} = shift;
    $self->{zoid_name} = shift;
    bless $self, $class;
    $self;
}

sub init {}

####################
#### some stubs ####
####################

sub parent {
    my $self = shift;
    return $self->{parent};
}

sub print {
    my $self = shift;
    $self->{parent}->print(@_);
}

sub config {
    my $self = shift;
    return $self->{config};
}

#####################
#### event logic ####
#####################

sub event {
	my $self = shift;
	my $event = shift;
	if ($self->can($event)) { $self->$event(@_); }
}

sub broadcast_event {
    my $self = shift;
    $self->parent->broadcast_event(@_);
}

sub register_event {
    my $self = shift;
    for (@_) { $self->parent->register_event($_, $self->{zoid_name}); }
}

sub unregister_event {
    my $self = shift;
    for (@_) { $self->parent->unregister_event($_, $self->{zoid_name}); }
}

sub unregister_all_events {
    my $self = shift;
    $self->parent->unregister_all_events($self->{zoid_name})
}

sub registered_events {
    my $self = shift;
    return $self->parent->registered_events($self->{zoid_name});
}

#####################
#### other stuff ####
#####################

sub help {
	my $self = shift;
	return "";
}

sub round_up {
    my $self = shift;
    # put shutdown sequence here -- like saving files etc.
}

sub DESTROY {
	my $self = shift;
	if ($self->parent->{round_up}) { $self->round_up; } # something went wrong -- unsuspected die
}

1;

__END__

=head1 NAME

Zoidberg::Fish - Base class for loadable Zoidberg plugins

=head1 SYNOPSIS

  package My::Dynamic::ZoidPlugin
  use base 'Zoidberg::Fish';

=head1 DESCRIPTION

  Base class for loadable Zoidberg plugins. Has many stubs
  to provide compatibility with Zoidberg

  Once this base class is used your module looks and smells
  like fish -- Zoidberg WILL eat it.

  See the user documentation on how to load these objects
  into Zoidberg.

=head1 METHODS

=head2 new($parent, \%config, $zoid_name)

  $self->{parent} a reference to parent Zoidberg object
  $self->{config} hash with some config
  $self->{zoid_name} name as known by parent object

=head2 init()

  To be overloaded, should be called by parent object.
  Do things like loading files, opening sockets here.

=head2 parent()

  Returns a reference to the Zoidberg object

=head2 print()

  Convenience method for calling ->parent->print

=head2 config()

  Return the config hash

=head2 event($event_name, @_)

  This method is called by the parent when an event is broadcasted

=head2 broadcast_event($event_name, @_)

  Calls ->parent->broadcast_event

=head2 register_event($event_name)

  Register an event with the parent object.
  When the event occurs, the `event' method will be called, with at least one argument: the event name.

=head2 unregister_event($event_name)

  Unregister self for event $event_name

=head2 unregister_all_events()

  Unregister self for all events

=head2 registered_events()

  List events self is registered for

=head2 help()

  Stub help function, should return a string
  with dynamic content for the zoidberg help system.

=head2 round_up()

  Is called when the plugin is unloaded or when sudden DESTROY occurs.
  To be overloaded, do things like saving files, closing sockets here

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

L<Zoidberg::Help>

L<http://zoidberg.sourceforge.net>

=cut

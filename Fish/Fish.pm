package Zoidberg::Fish;

our $VERSION = '0.1';

sub isFish { return 1; }

sub new {
    my $class = shift;
    my $self = {};
    $self->{parent} = shift;
    $self->{config} = shift;
    $self->{zoid_name} = shift;
    bless $self, $class;
}

sub init {
	my $self = shift;
	# insert init routine here
}

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
	if ($self->can($event)) { $self->$event(@_); } # hack around old event style -- is this to stay ?
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
	if (!$self->parent->{rounded_up} && $self->parent->{round_up}) { $self->round_up; }
}

1;
__END__

=head1 NAME

Zoidberg::Fish - Base class for loadable Zoidberg plugins

=head1 SYNOPSIS

  package My::Dynamic::ZoidPlugin
  use base 'Zoidberg::Fish';

=head1 DESCRIPTION

  Base class for loadable Zoidberg plugins has many stubs
  to provide compatability with Zoidberg

  Ones this base class is used your module looks and smells
  like fish -- Zoidberg WILL eat it.

  See other (?) documentation on how to load these objects
  in Zoidberg.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 new($parent, \%config, $zoid_name)

  $self->{parent} a reference to parent Zoidberg object
  $self->{config} hash with some config
  $self->{zoid_name} name as known by parent object

=head2 init()

  To be overloaded, should be called by parent object.
  Do things like loading files here.

=head2 parent()

  returns ref to parent

=head2 print()

  calls parent->print

=head2 config()

  return ref to config

=head2 event($event_name, @_)

  is called by parent when event is broadcasted

=head2 broadcast_event($event_name, @_)

  calls parent->broadcast_event

=head2 register_event($event_name)

  register self by parent for event $event_name
  this means that when this event occurs
  $self->event is called

=head2 unregister_event($event_name)

  unregister self for event $event_name

=head2 unregister_all_events()

  unregister self for event all events

=head2 registered_events()

  list events self is registered for

=head2 help()

  Stub help function, should return string
  with dynamic content for the zoidberg help system.

=head2 round_up()

  Is called when parent wants to stop
  or when sudden DESTROY occurs
  To be overloaded, do things like saving files here

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

package Zoidberg::Fish;

our $VERSION = '0.42';

sub new {
	my ($class, $zoid, $name) = @_;
	my $self = {
		parent => $zoid,
		zoidname => $name,
		settings => $zoid->{settings},
		config => $zoid->{settings}{$name},
	};
	bless $self, $class;
}

sub init {}

# ########## #
# some stubs #
# ########## #

sub parent {
    my $self = shift;
    return $self->{parent};
}

sub config {
    my $self = shift;
    return $self->{config};
}

# ########### #
# event logic #
# ########### #

sub broadcast {
	my $self = shift;
	$self->{parent}->broadcast(@_);
}

sub register_event { # DEPRECATED interface
	my ($self, $event, $zoidname) = @_;
	$zoidname ||= $self->{zoidname};
	$self->{parent}{events}{$event} = ["->$zoidname->$event", $zoidname];
}

sub unregister_event { todo() }

# ############# #
# command logic #
# ############# #

# TODO interface access to command dispatch table here

# ########### #
# other stuff #
# ########### #

sub add_context {
	my ($self, %context) = @_;
	my $cname = delete($context{name}) || $$self{zoidname};
	$self->{parent}{contexts}{$cname} = [\%context, $$self{zoidname}];
	# ALERT this logic might change
}

sub help {
	my $self = shift;
	return "";
}

sub round_up {} # put shutdown sequence here -- like saving files etc.


sub DESTROY {
	my $self = shift;
	if ($self->parent->{round_up}) { $self->round_up; } # something went wrong -- unsuspected die
}

1;

__END__

=head1 NAME

Zoidberg::Fish - Base class for loadable Zoidberg plugins

=head1 SYNOPSIS

  package My_Zoid_Plugin;
  use base 'Zoidberg::Fish';

  FIXME some example code

=head1 DESCRIPTION

Once this base class is used your module smells like fish -- Zoidberg WILL eat it.
It supplies stub methods for hooks and has some routines to simplefy the interface to
Zoidberg. One should realize that the bases of a plugin is not the module but
the config file. Any module can be used as plugin as long as it's properly configged.
The B<developer manual> should describe this in more detail.

=head1 METHODS

=over 4

=item C<new($parent, $zoidname)>

Simple constructor that bootstraps same attributes. When your module smells like fish
Zoidberg will give it's constructor two arguments, a reference to itself and the name by
which your module is identified. From this all other config can be deducted.

	# Default attributes created by this constructor:
 
	$self->{parent}    # a reference to parent Zoidberg object
	$self->{zoidname} # name by which your module is identified
	$self->{settings}  # reference to hash with global settings
	$self->{config}    # hash with plugin specific config

=item C<init()>

To be overloaded, will be called directly after the constructor. 
Do things you normally do in the constructor like loading files, opening sockets 
or setting defaults here.

=item C<parent()>, C<config()>

These methods return a reference to the attributes by the same name.

=item C<broadcast($event_name, @_)>

Broadcast an event to whoever might be listening.

=item C<register_event($event_name)>

Register for an event by the parent object. When the event occurs, the C<event()> method 
will be called.

DEPRECATED

=item C<unregister_event($event_name)>

Unregister self for event C<$event_name>.

DEPRECATED / TODO :S

=item C<help()>

Stub help function, to be overloaded. This method should return a string
with B<dynamic> content for the zoidberg help system. Static help content
should be formatted as a seperate pod file.

=item C<round_up()>

Is called when the plugin is unloaded or when a sudden DESTROY occurs.
To be overloaded, do things like saving files or closing sockets here.

=back

=head1 AUTHOR

R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>,
L<http://zoidberg.sourceforge.net>

=cut

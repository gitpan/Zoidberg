package Zoidberg::Fish;

our $VERSION = '0.3a_pre1';

#use Zoidberg::Fish::Crab;

sub new {
    my $class = shift;
    my $self = {};
    $self->{parent} = shift;
    $self->{zoid_name} = shift;
    $self->{settings} = $self->{parent}{settings};
    $self->{config} = $self->{parent}{plugins}{$self->{zoid_name}}{config};
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
	$self->{parent}->broadcast_event(@_);
}

sub register_event {
	my $self = shift;
	my $event = shift;
	my $zoidname = shift || $self->{zoid_name};
	unless (exists $self->{parent}{events}{$event}) { $self->{parent}{events}{$event} = [] }
	push @{$self->{parent}{events}{$event}}, $zoidname;
}

sub registered_events {
	my $self = shift;
	my $zoidname = shift || $self->{zoid_name};
	my @events = ();
	foreach my $event (keys %{$self->{parent}{events}}) {
		if (grep {$_ eq $zoidname} @{$self->{parent}{events}{$event}}) { push @events, $event; }
	}
	return @events;
}

sub registered_objects {
	my $self = shift;
	my $event = shift;
	return @{$self->{parent}{events}{$event}};
}

sub unregister_event {
	my $self = shift;
	my $event = shift;
	my $zoidname = shift || $self->{zoid_name};
	@{$self->{parent}{events}{$event}} = grep {$_ ne $zoidname} @{$self->{parent}{events}{$event}};
}

sub unregister_all_events {
	my $self = shift;
	foreach my $event (keys %{$self->{parent}{events}}) { $self->unregister_event($event, @_) }
}

######################
### command logic ####
######################

# TODO implement a hash of commands in parent, access through interface here

#####################
#### other stuff ####
#####################

sub _do_sub {
	my $self = shift;
	my $ding = shift;
	my @args = @_;
	if (ref($ding) eq 'CODE') { $ding->($self, @args) }
	elsif (ref($ding)) { die "Can't use a ".ref($ding)." reference as sub routine." }
	else {
		$ding =~ s/^\s*//;
		unless ($ding =~ /^\$/) { 
			$ding =~ s/^->/parent->/;
			$ding = '$self->'.$ding;
		}
		
		if ($ding =~ s/(\(.*\))\s*$//) { unshift @args, eval($1) }
		my $sub = eval("sub { $ding(\@_) }");
		return $sub->(@args);
	}
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

=item C<new($parent, $zoid_name)>

Simple constructor that bootstraps same attributes. When your module smells like fish
Zoidberg will give it's constructor two arguments, a reference to itself and the name by
which your module is identified. From this all other config can be deducted.

	# Default attributes created by this constructor:
 
	$self->{parent}    # a reference to parent Zoidberg object
	$self->{zoid_name} # name by which your module is identified
	$self->{settings}  # reference to hash with global settings
	$self->{config}    # hash with plugin specific config

=item C<init()>

To be overloaded, will be called directly after the constructor. 
Do things you normally do in the constructor like loading files, opening sockets 
or setting defaults here.

=item C<parent()>, C<config()>

These methods return a reference to the attributes by the same name.

=item C<print()>

Prefered output method.

FIXME this one might move to helper library

=item C<_do_sub($thing)>

Execute subroutine specified by string C<$thing> or execute C<$thing> directly
when it's a CODE ref. It works the same way like Zoidberg executes commands, with the
difference it takes the subroutine as base instead of the parent object. It is preferred 
to use this for "command-like" configuration options.

=item C<event($event_name, @_)>

This method is called by the parent object when an event is broadcasted for which this
plugin is registered.

=item C<broadcast_event($event_name, @_)>

Broadcast an event to whoever might be listening.

=item C<register_event($event_name)>

Register for an event by the parent object. When the event occurs, the C<event()> method 
will be called.

=item C<unregister_event($event_name)>

Unregister self for event C<$event_name>.

=item C<unregister_all_events()>

Unregister self for all events, this is by default called by C<round_up()>. It is good practice 
to call this routine when a plugin signs off.

FIXME this is what _should_ happen -- but events need to get more efficient

=item C<registered_events()>

List events self is registered for.

=item C<help()>

Stub help function, to be overloaded. This method should return a string
with B<dynamic> content for the zoidberg help system. Static help content
should be formatted as a seperate pod file.

=item C<round_up()>

Is called when the plugin is unloaded or when a sudden DESTROY occurs.
To be overloaded, do things like saving files or closing sockets here.

=back

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

L<Zoidberg::Help>

L<http://zoidberg.sourceforge.net>

=cut

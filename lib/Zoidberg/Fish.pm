package Zoidberg::Fish;

our $VERSION = '0.51';

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

sub parent { $_[0]->{parent} }

sub config { $_[0]->{config} }

# #################### #
# event and hook logic #
# #################### #

sub call {
	my ($self, $event) = (shift, shift);
	return $$self{parent}{events}{$event}->(@_)
		if exists $$self{parent}{events}{$event};
	return ();
}

sub broadcast {
	my $self = shift;
	$self->{parent}->broadcast(@_);
}

sub register_event {
	my ($self, $event, $method) = @_;
	$method ||= $event;
	$method = '->'.$$self{zoidname}.'->'.$method 
		unless ref $method or $method =~ /^->/;
	$$self{parent}{events}{$event} = [$method, $$self{zoidname}];
}

sub unregister_event { todo() }

# ############# #
# command logic #
# ############# #

# TODO interface access to command dispatch table here

# ########### #
# other stuff #
# ########### #

sub ask {
	my ($self, $quest, $def) = @_;
	$quest .= ($def =~ /^n$/i) ? ' [yN] '
		: ($def =~ /^y$/i) ? ' [Yn] ' : " [$def] " if $def ;
	my $ans = $self->call('readline', $quest);
	return $ans =~ /y/i if $def =~ /^[ny]$/i;
	$ans =~ s/^\s*|\s*$//g;
	return length($ans) ? $ans : $def ;
}

sub add_context { # ALERT this logic might change
	my ($self, %context) = @_;
	my $cname = delete($context{name}) || $$self{zoidname};
	my $fp = delete($context{from_package});
	my $nw = delete($context{no_words});
	for (values %context) { $_ = "->$$self{zoidname}->".$_ unless /^\W/ }
	if ($fp) { # autoconnect
		$self->can($_) and $context{$_} ||= "->$$self{zoidname}->$_"
			for qw/word_list handler intel filter parser/;
	}
	for (qw/word_list filter/) { # stacks
		$self->{parent}{contexts}{$_} = delete $context{$_}
			if exists $context{$_};
	}
	if ($nw) { # no words
		push @{$$self{parent}{no_words}}, $cname;
	}
	$self->{parent}{contexts}{$cname} = [\%context, $$self{zoidname}];
	return $cname;
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

=item C<call($event, @args)>

Call a hook (implemented as an event). Use this to glue plugins.

=item C<broadcast($event_name, @_)>

Broadcast an event to whoever might be listening.

=item C<register_event($event_name, $method)>

Register for an event by the parent object.
When the event occurs, the method C<$method> will be called.
C<$method> is optional and defaults to the event name.
C<$method> can also be a CODE reference.

=item C<unregister_event($event_name)>

Unregister self for event C<$event_name>.

TODO

=item C<ask($question, $default)>

Get interactive input. The default is optional.
If the default is either 'Y' or 'N' a boolean value is returned.

=item C<round_up()>

Is called when the plugin is unloaded or when a sudden DESTROY occurs.
To be overloaded, do things like saving files or closing sockets here.

=item C<add_context(%config)>

FIXME / see man zoiddevel

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

package Zoidberg::Fish::Monitor;

our $VERSION = '0.2';

use strict;
use Zoidberg::PdParse;

use base 'Zoidberg::Fish';

sub init {
    my $self = shift;
    $self->{config}{applets} = pd_read($self->{config}{applet_file});
    foreach my $event (keys %{$self->{config}{applets}}) {
    	foreach my $applet (keys %{$self->{config}{applets}{$event}}) {
		$self->{applets}{$event}{$applet} = {
			'condition' => sub {eval($self->{config}{applets}{$event}{$applet}{condition})},
			'action' => sub {eval($self->{config}{applets}{$event}{$applet}{action})},
		};
	}
    	$self->register_event($event);
    }
}


sub event {
	my $self = shift;
	my $event = shift;
	#print "debug: got event $event\n";
	map { if ($_->{condition}->(@_)) { $_->{action}->($self, @_); } } values %{$self->{applets}{$event}};
}

sub list {
    my $self = shift;
    my $mode = defined wantarray?'message':'';
    $self->parent->print("The following applets are currently running: ",$mode);
    map {$self->parent->print("$_\n",$mode)} map {"event ".$_.":\n".join("\n", keys %{$self->{applets}{$_}}) } keys %{$self->{applets}};
    if (defined wantarray) {
        return [keys%{$self->{applets}}];
    }
}

sub add_applet {
	my $self = shift;
	my ($name, $event, $condition, $action) = @_;
	$self->{config}{applets}{$event}{$name} = { 'condition' => $condition, 'action' => $action };
	$self->{applets}{$event}{$name} = { 'condition' => sub {eval($condition)}, 'action' => sub {eval($action)} };
	unless (grep {/^$event$/} $self->registered_events) { $self->register_event($event); }
}

sub delete_applet {
    my $self = shift;
    my $name = shift;
    for (grep { grep {/^$_$/} keys %{$self->{applets}{$_}} } keys %{$self->{applets}}) {
    	delete $self->{applets}{$_}{$name};
	delete $self->{config}{applets}{$_}{$name};
    }
}

sub round_up {
    my $self = shift;
    if ($self->parent->{shell}{round_up}) {
    	pd_write($self->{config}{applet_file}, $self->{config}{applets}) || print "file write failed\n";
    }
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Zoidberg::Fish::Monitor - simple event monitoring

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 ABSTRACT

  Simple event monitoring in the Zoidberg shell.

=head1 DESCRIPTION

This plugin allows you monitor events in a simple way.
You define a applet for a event by two blocks of code,
the first returning a boolean, the second doing some obscure
thingies. At the specified event if the first block returns
 1 the second block is executed.
 
This module is a nice example on how to use events in Zoidberg.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 list()

  print applets in use

=head2 add_applet($name, $event_name, $condition, $action)

  start using an extra applet
  $name should be unique
  $condition and $action are both perl code as string

=head2 delete_applet($applet_name)

  never see applet $applet_name again

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>
Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net.

=cut

package Zoidberg::Monitor;

use strict;

use base 'Zoidberg::Fish';

use Zoidberg::Monitor::Applet;

sub postinit {
    my $self = shift;
    $self->{config}{applets} = $self->parent->pd_read($self->{config}{applet_file});
    for (keys %{$self->{config}{applets}}) {
        my $applet = Zoidberg::Monitor::Applet->new;
        $applet->init($self,{name=>$_,%{$self->{config}{applets}{$_}}});
        $self->register($applet);
    }
}

sub help {
    my $self = shift;
    return <<"EOH";
Help for Zoidberg::Monitor

The monitor subsystem can be used for running applets inside the zoid.
These applets have the following properties:

name: unique name used to identify the applet
interval: interval in seconds at which the applet in run
condition: a subroutine which does arbitrary voodoo to decide whether to return true
event: a subroutine that acts when the condition is true (notify user, kill process, turn off lights)

To get a list of running applets:
Monitor->list

You can register a new applet using the following syntax:
Monitor->register("foo",4,sub{},sub{})

Or delete an applet:
Monitor->delete("foo")

You can also get access to the applet object itself:
Monitor->applet('foo')

... and manipulate it
Monitor->applet('foo')->interval(972)

... or unregister it
Monitor->applet('foo')->delete

EOH
}

sub list {
    my $self = shift;
    $self->print("The following applets are currently running: ");
    map {$self->print("\t $_\n")} keys %{$self->{applets}};
}

sub dump {
    my $self = shift;
    my $parent = delete $self->{parent};
    use Data::Dumper;
    print Dumper($self);
    $self->{parent}=$parent;
}

sub precmd {
    my $self = shift;
    map {$_->run} $self->applets;
}

sub postcmd {
    my $self = shift;
}

sub artohas { {name=>shift,interval=>shift,condition=>shift,event=>shift } }
    
sub register {
    my $self = shift;
    if (ref($_[0]) =~ /Applet/) {
        $self->{applets}{$_[0]->name} = $_[0];
    }
    else {
        my $config;
        if (ref($_[0])eq'HASH') {
            $config = shift;
        }
        elsif (ref($_[0])eq'ARRAY') {
            $config = artohas(@{$_[0]});
        }
        elsif (scalar@_==4) {
            $config = artohas(@_);
        }
        elsif (scalar@_==1) {
            if (exists$self->{config}{applets}{$_[0]}) {
                $config = {name => $_[0], %{$self->{config}{applets}{$_[0]}}};
            }
        }
        my $applet = Zoidberg::Monitor::Applet->new;
        $applet->init($self,$config);
        $self->{applets}{$applet->name}=$applet;
    }
}

sub delete {
    my $self = shift;
    if (ref($_[0]) =~ /Applet/) {
        $_[0]->delete;
    }
    else {
        delete $self->{applets}{$_[0]};
        delete $self->{config}{applets}{$_[0]};
    }
}

sub applet {
	my $self = shift;
	if ($self->{applets}{$_[0]}) {
		return $self->{applets}{$_[0]};
	}
}

sub unregister {
    my $self = shift;
    if (ref($_[0]) =~ /Applet/) {
        delete $self->{applets}{grep{"$_" eq "$_[0]"}$self->applets} and return 1;
    }
    if ($self->{applets}{$_[0]}) {
        delete $self->{applets}{$_[0]};
    }
    return 0;
}

sub applets {
    my $self = shift;
    return values %{$self->{applets}};
}

sub round_up {
    my $self = shift;
    for ($self->applets) {
        unless (exists $self->{config}{applets}{$_}) {
            $_->save;
        }
    }
    $self->write_data;
    # write applet object data to .pd file:)
}

sub write_data {
    my $self = shift;
    #$self->parent->pd_write('../etc/monitor.pd',$self->{config}{applets}) || print "file write failed\n";
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Zoidberg::Monitor - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::Monitor;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for Zoidberg::Monitor.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for Zoidberg::Monitor, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Raoul Zwart, E<lt>carlos@internal.cyberhqz.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002 by Raoul Zwart

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

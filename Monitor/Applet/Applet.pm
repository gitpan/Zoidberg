package Zoidberg::Monitor::Applet;

use strict;
use warnings;

use base 'Zoidberg::Fish';

sub condition {
    my $self = shift;
    unless (ref($self->{config}{condition}) eq 'CODE') {return 0}
    $self->{config}{condition}->($self);
}

sub unregister {
    my $self = shift;
    $self->parent->unregister($self);
}

sub register {
    my $self = shift;
    $self->parent->register($self);
}

sub save {
    my $self = shift;
    $self->parent->{config}{applets}{$self->name} = $self->{config};
}

sub delete {
    my $self = shift;
    delete $self->parent->{applets}{$self->name};
    delete $self->parent->{config}{applets}{$self->name};
}

sub lastrun {
    my $self = shift;
    unless (exists $self->{lastrun}) {
        $self->{lastrun} = 0;
    }
    if (@_) {
        $self->{lastrun} = shift;
    }
    else {
        $self->{lastrun};
    }
}

sub run {
    my $self = shift;
    unless ($self->interval) { return 0 }
    if (time > ($self->lastrun + $self->interval)) {
        $self->condition && $self->event;
        $self->lastrun(time);
        return 1;
    }
    return 0;
}

sub postinit {
    my $self = shift;
    $self->lastrun(time);
}

sub event {
    my $self = shift;
    unless (ref($self->{config}{event}) eq 'CODE') { return 0 }
    $self->{config}{event}->($self);
}

sub name {
    my $self = shift;
    return $self->{config}{name};
}

sub interval {
    my $self = shift;
    if ($_[0]) {
        $self->{interval} = shift;
    }
    return (ref($self->{config}{interval})eq'CODE')?$self->{config}{interval}->($self):$self->{config}{interval};
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Zoidberg::Monitor::Applet - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::Monitor::Applet;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for Zoidberg::Monitor::Applet.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for Zoidberg::Monitor::Applet, created by h2xs. It looks like the
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

root, E<lt>root@internal.cyberhqz.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002 by root

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

package Zoidberg::Help;

use strict;
use warnings;

use base 'Zoidberg::Fish';

sub register_events {
    my $self = shift;
    $self->register_event('postcmd');
        # imagine this......:)
        # you seem to have made booboo #427, please try the following: $->{[%{}]}:)
}

sub modules {
    my $self = shift;
    # return all active modules that have a help method
    grep {$self->{parent}{objects}{$_}->can('help')&&!/Help/} @{$self->{parent}->list_objects};
}

sub help {
    my $self = shift;
    unless (@_) {
        # eigen help... 
        $self->print("Welcome to the Zoidberg help system.");
        $self->print("\nHelp is available for the following modules:\n\n");
	$self->print("\taliases\n\tobjects\n\n");
        for ($self->modules) {
            $self->print("\t$_\n");
        }
        $self->print("\nType 'help Modulename' to view the module's help\n");
        return 1;
    }
    my $mod = shift;
    if (grep/$mod/i, @{$self->parent->list_objects}) {
        my $o = $self->parent->$mod;
        if ($o->can('help')) {
            $self->print($o->help(@_));
        }
        else {
            $self->print("No help found for module $mod\n");
        }
    }
    elsif ($self->can("help_".$mod)) {
        my $sub = "help_".$mod;
        $self->$sub;
    }
    else {
        $self->print("Module $mod not found");
    }
}

sub help_aliases {
    my $self = shift;
    $self->print("The following aliases are currently defined:\n\n");
    foreach my $alias (@{$self->parent->list_aliases}) {
        $self->print("\t$alias = ".$self->parent->alias($alias)."\n");
    }
}

sub help_objects {
    my $self = shift;
    $self->print("The following objects are loaded:\n\n");
    foreach my $object (@{$self->parent->list_objects}) {
        $self->print("\t$object\n");
    }
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Zoidberg::Help - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::Help;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for Zoidberg::Help.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for Zoidberg::Help, created by h2xs. It looks like the
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

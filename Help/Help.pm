package Zoidberg::Help;

our $VERSION = '0.04';

use strict;
use warnings;

use base 'Zoidberg::Fish';
use Devel::Symdump;

sub init {
    my $self = shift;
    $self->{config}{dir} =~ s/\/?$/\//;
    #$self->register_event('postcmd');
        # imagine this......:)
        # you seem to have made booboo #427, please try the following: $->{[%{}]}:)
}

sub help {
    my $self = shift;
    my $warning = " The Zoidberg shell is still in developement, do not be surprised if options do not work as described above.";
    unless (@_) {
        # help index
	$self->print("Welcome to the Zoidberg help system.\n  Help is available for the following subjects:\n\n");
	$self->print("\n  Build in:\n");
	for (sort $self->get_specials) { $self->print("\t$_\n"); }
	$self->print("\n  Modules:\n");
        for (sort $self->get_objects) { $self->print("\t$_\n"); }
	$self->print("\n  Other:\n");
	for (sort $self->get_files) { $self->print("\t$_\n"); }
        $self->print("\n  Type 'help \$subject' for help on a certain subject.\n");
        return 1;
    }
    my $subject = shift;
    my @args = @_;
    if (my ($name) = grep/$subject/i, $self->get_objects) {
        my $o = $self->parent->object($name);
        my $file = ref($o);
	$file =~ s/\:\:/\//g; #/
        my $body = $self->read_file($file);
        if ($o->can('help')) { $body .= $o->help(@args); }
	if ($body =~ /^\s*$/) { $self->print('This module seems to have no help available.'); }
	else {
		$self->print($body);
		$self->print($warning, 'warning');
	}
    }
    else {
    	my $body = $self->read_file($subject);
    	my $sub = "help_".$subject;
	if ($self->can($sub)) { $body .= $self->$sub; }
	if ($body =~ /^\s*$/) { $self->print("No help found for \'$subject\'."); }
	else {
		$self->print($body);
		$self->print($warning, 'warning');
	}
    }
}

sub get_specials {
	my $self = shift;
	return map {s/^help_//;$_} grep {/^help_/} map {s/^(.+\:\:)*//g; $_} (Devel::Symdump->new(ref($self))->functions);
}

sub get_objects {
    my $self = shift;
    # return all active modules that have a help method
    return grep {$self->parent->object($_)->can('help')&&!/Help/} @{$self->parent->list_objects};
}

sub get_files {
	my $self = shift;
	opendir DIR, $self->{config}{dir};
	my @dinge = readdir DIR;
	closedir DIR;
	return grep {-f $self->{config}{dir}.$_} @dinge;
}

sub read_file {
	my $self = shift;
	my $arg = shift;
	my ($file) = grep {/^$arg$/i} $self->get_files;
	if ($file) {
		open IN, $self->{config}{dir}.$file;
		my @r = <IN>;
		close IN;
		return join("", @r);
	}
	return '';
}

sub list { # list subjects -- for tab expansion
	my $self = shift;
	my @subj = ();
	push @subj, $self->get_specials;
	push @subj, $self->get_objects;
	push @subj, $self->get_files;
        return [sort @subj];
}

###########################
#### Build-in specials ####
###########################

sub help_version {
	my $self = shift;
	return $Zoidberg::LONG_VERSION;
}

sub help_aliases {
    my $self = shift;
    my $body = "The following aliases are currently defined:\n\n";
    foreach my $alias (sort @{$self->parent->list_aliases}) {
        $body .= "\t$alias\t=\t".$self->parent->alias($alias)."\n";
    }
    return $body;
}

sub help_objects {
    my $self = shift;
    my $body = "The following objects are loaded:\n\n";
    foreach my $object (@{$self->parent->list_objects}) {
        $body .= "\t$object\t=\t".ref($self->parent->object($object))."\n";
    }
    return $body;
}


1;
__END__

=head1 NAME

Zoidberg::Help - Generates help texts for zoidberg

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 ABSTRACT

  This module generates help texts for zoidberg.

=head1 DESCRIPTION

This module generates help texts for zoidberg.
It uses the help() method of other plugins and searches 
for help files in $prefix/share/zoid/help.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 help($subject)

  Get help about $subject
  if subject is ommitted list subjects

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net

=cut


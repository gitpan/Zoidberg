package Zoidberg::Help;

our $VERSION = '0.1';

use strict;

use base 'Zoidberg::Fish';
use Devel::Symdump;
use Data::Dumper;
use Pod::Text::Color;
use IO::File;

sub init {
    my $self = shift;
    $self->{config}{dir} =~ s/\/?$/\//;
    #$self->register_event('postcmd');
        # imagine this......:)
        # you seem to have made booboo #427, please try the following: $->{[%{}]}:)
}

sub help {
    my $self = shift;
    my ($subject, @args) = split / /, shift;
    my $warning = "This is a developement version -- do not be surprised if options do not work as described above.";
    unless ($subject) {
	$self->print_index;
	return 1;
    }
    if ($self->{config}{aliases}{$subject}) { $subject = $self->{config}{aliases}{$subject}; }

    if (my ($name) = grep/^$subject/i, $self->get_objects) {
        my $o = $self->parent->object($name);
        my $file = ref($o);
	$file =~ s/\:\:/\//g; #/
        my $bit = $self->print_file($file);
        if ($o->can('help')) {
		$self->print($o->help(@args));
		$bit++;
	}
	unless ($bit) { $self->print('This module seems to have no help available.'); }
	elsif (ref($self->parent)."::DEVEL") { $self->print($warning, 'warning'); }
    }
    else {
	($subject) = grep /^$subject/i, ($self->get_specials, $self->get_files);
	my $bit = $self->print_file($subject);
	my $sub = "help_".$subject;
	if ($self->can($sub)) {
		$self->print($self->$sub(@args));
		$bit++;
	}
	unless ($bit) { $self->print("No help found for \'$subject\'."); }
	elsif (ref($self->parent)."::DEVEL") { $self->print($warning, 'warning'); }
    }
}

sub print_index {
	my $self = shift;
	$self->parent->print("Welcome to the Zoidberg help system.\n  Help is available for the following subjects:\n\n");
	my @subjects = ();
	push @subjects, ("\n  Build in:", map {'    '.$_} sort $self->get_specials);
	push @subjects, ("\n  Modules:", map {'    '.$_} sort $self->get_objects);
	push @subjects, ("\n  Other:", map {'    '.$_} sort $self->get_files);
	print join("\n", @subjects);
        $self->parent->print("\n\n  Type 'help \$subject' for help on a certain subject.\n");
}

sub print_file {
	my $self = shift;
	my $file = shift;
	unless (-e $self->{config}{dir}.$file) {($file) = grep {/^$file$/i} $self->get_files; }
	if ($file && -s $self->{config}{dir}.$file) {
		#print "debug: trying to read: ".$self->{config}{dir}.$file."\n";
		my $fh_in = IO::File->new($self->{config}{dir}.$file);
		unless (defined $fh_in) { return 0; }
		my $parser = Pod::Text::Color->new(sentence => 0, width => ($self->parent->Buffer->size)[0]);
		$parser->parse_from_filehandle($fh_in);
		$fh_in->close;
		return 1;
	}
	return 0;
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

sub intel {
	my $self = shift;
	my ($set, $block, $intel) = @_;

	if ($block =~ /^\s*(\w+)?$/) {
		if (defined ($set = $intel->set_arg($set, $1))) {
			push @{$set->{poss}}, sort grep /$set->{arg}/i, @{$self->list};
			$set->{postf} = ' ';
			$set->{reg_opt} = 'i';
			$intel->add_poss($set);
		}
	}
	else {} # dunno yet

	return $set;
}

sub list { # list subjects -- for tab expansion
	my $self = shift;
	my @subj = ();
	push @subj, $self->get_specials;
	push @subj, $self->get_objects;
	push @subj, $self->get_files;
        return [@subj];
}

###########################
#### Build-in specials ####
###########################

sub help_version {
	my $self = shift;
	return join("\n", map {'  '.$_} split(/\n/, $Zoidberg::LONG_VERSION));
}

sub help_aliases {
    my $self = shift;
    my $body = "The following aliases are currently defined:\n\n";
    foreach my $alias (@{$self->parent->list_aliases}) { $body .= "\t$alias->[0]\t=\t$alias->[1]\n"; }
    return $body;
}

sub help_objects {
    my $self = shift;
    my $body = "The following objects are loaded:\n\n";
    foreach my $object (@{$self->parent->list_objects}) { $body .= "\t$object\t=\t".ref($self->parent->object($object))."\n"; }
    return $body;
}

sub help_class {
	my $self = shift;
	my $class = shift;
	unless ($class) { return "Use this function with a class name as argument to view pod."; }
	else {
		my $file = $class;
		$file =~ s{::}{/}g;
		$file .= ".pm";
		$file = $INC{$file};
		unless ($file) { return "Could not find source file for $class."; }
		else {
			my $fh_in = IO::File->new($file);
			unless (defined $fh_in) { return "Error while reading $file"; }
			my $parser = Pod::Text::Color->new(sentence => 0, width => ($self->parent->Buffer->size)[0]);
			$parser->parse_from_filehandle($fh_in);
			$fh_in->close;
		}
	}
	return '--';
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


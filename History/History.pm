package Zoidberg::History;

our $VERSION = '0.1';

use strict;
use Zoidberg::PdParse;

use base 'Zoidberg::Fish';

# @{$self->{data}{hist}} = [ [command, \@_, \%prop], .. ]
# whereby @_ is the last entered set for this command

sub init {
	my $self = shift;
	if ($self->{config}{hist_file} && -s $self->{config}{hist_file}) {
		$self->{data} = pd_read($self->{config}{hist_file});
		$self->{data}{hist_p} = 0;
	}
	else {
		$self->{data} = {
			'hist' => [ ['', [], {}] ],
			'hist_p' => 0,
			'dir_hist' => {
				'next' => [''],
				'prev' => [''],
			},
		}
	}
}

sub add {
	my $self = shift;
	if (my $string = shift) {
		$string =~ s/([\'\"])/\\$1/g;
		$string = '\''.$string.'\'';
		#print "debug: going to add to hist: ".join('--', $string, @_)."\n";

		unless ($string eq $self->{data}{hist}[1][0]) {
			my $record = [ $string, [@_], { 'time' => time, 'redun' => 1, } ];
			$self->broadcast_event("history_add",$record);

			splice(@{$self->{data}{hist}}, 0, 1, (['', [], {}], $record));

			my $max = $self->{config}{max_hist} || 100;
			if ($#{$self->{data}{hist}} > $max) { pop @{$self->{data}{hist}}; }
		}
		elsif ($string eq $self->{data}{hist}[1][0]) {
			$self->{data}{hist}[1][1] = [@_];
			$self->{data}{hist}[1][2]{redun}++;
		}
	}
	$self->{data}{hist_p} = 0; # reset history pointer
}

sub get {
	# arg: undef or "current" || "prev" || "next"
	# arg: int next or prev
	my $self = shift;
	my $act = shift;
	my $int = shift || 1;
	if ($act eq "prev") {
		if ($self->{data}{hist_p} + $int < $#{$self->{data}{hist}}) { $self->{data}{hist_p} += $int; }
		else { $self->{data}{hist_p} = $#{$self->{data}{hist}}; }
	}
	elsif ($act eq "next") {
		if ($self->{data}{hist_p} - $int > 0) { $self->{data}{hist_p} -= $int; }
		else { $self->{data}{hist_p} = 0; }
	}
	my @record = @{$self->{data}{hist}[$self->{data}{hist_p}]};
	$record[0] =~ s/(^\'|\'$)//g;
	$record[0] =~ s/\\([\'\"])/$1/g;
	return @record;
}

sub list {
	my $self = shift;
	return [ map {
			my $dus = $_->[0];
			$dus =~ s/(^\'|\'$)//g;
			$dus =~ s/\\([\'\"])/$1/g;
			$dus;
		} @{$self->{data}{hist}}[1..$#{$self->{data}{hist}}]
	] ;
}

sub del {
	my $self = shift;
	my $off = shift || 1;
	my $len = shift || 1;
	my @removed = splice(@{$self->{data}{hist}}, $off, $len);
	$self->broadcast_event("history_delete", @removed);
}

sub set_prop {
	my $self = shift;
	my $prop = shift;
	my $value = shift;
	my $index = shift || 1;
	$self->{data}{hist}[$index][2]{$prop} = $value;
}

sub get_prop {
	my $self = shift;
	my $prop = shift;
	my $index = shift || 1;
	return $self->{data}{hist}[$index][2]{$prop} || '';
}

sub search {
	my $self = shift;
}

sub show {
	my $self = shift;
}

##################
#### dir hist ####
##################

sub add_dir {
	my $self = shift;
	my $dir = shift || $ENV{PWD};
	#print "debug: got dir $dir to add to dir hist\n";
	unless ($dir eq $self->{data}{dir_hist}{prev}[0]) {
		unshift @{$self->{data}{dir_hist}{prev}}, $dir;
	}
}

sub get_dir {
	my $self = shift;
	my $return = $ENV{PWD};
	if (($_[0] eq "next")||($_[0] eq "forw")) {
		$return = pop @{$self->{data}{dir_hist}{next}} || '';
		if ($return && ($return ne $self->{data}{dir_hist}{prev}[0])) {
			unshift @{$self->{data}{dir_hist}{prev}}, $ENV{PWD};
		}
	}
	elsif (($_[0] eq "prev")||($_[0] eq "back")) {
		$return = shift @{$self->{data}{dir_hist}{prev}} || '';
		if ($return && ($return ne $self->{data}{dir_hist}{next}[-1])) {
			push @{$self->{data}{dir_hist}{next}}, $ENV{PWD};
		}
	}
	else { return $ENV{PWD}; }
	$self->dir_check_max;
	return $return;
}

sub dir_check_max {
	my $self = shift;
	my $max = $self->{config}{max_dir_hist} || 5;
	if ($#{$self->{data}{dir_hist}{prev}} > $max) {
		pop @{$self->{data}{dir_hist}{prev}};
	}
	if ($#{$self->{data}{dir_hist}{next}} > $max) {
		shift @{$self->{data}{dir_hist}{next}};
	}
}

##############
#### rest ####
##############

sub round_up {
	my $self = shift;
	if ($self->{config}{hist_file}) {
		unless (pd_write($self->{config}{hist_file}, $self->{data})) {
			$self->print("Failed to write history file: ".$self->{config}{hist_file}, 'error');
		}
	}
}

1;
__END__

=head1 NAME

Zoidberg::History - History plugin for the Zoidberg shell

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 ABSTRACT

  This module provides history functionality for
  the zoidberg shell.

=head1 DESCRIPTION

This module provides history functionality for the
zoidberg shell. It is a core plugin.

=head2 EXPORT

None by default.

=head1 DATA

The history records used by this module are of the format: [ $command_string, \@arguments, \%properties ].

The command string simply simply be the command as entered on the prompt.

The array arguments are environment vars suppleid by the buffer -- the history just stores them
but does not use them in any way.

The properties hash contains meta data used by both history and other plugins.
It is possible to add any property to a history record, see METHODS for the api,
default implemented are: "time"	=> touch time, "redun" => number of times the same command was entered,
and "exec"  => if true the command really was executed. This last property is set by Zoidberg::Buffer.

=head1 METHODS

=over 4

=item B<add($string, @args)>

Stores both string and array arguments in history

=item B<get($action, $int)>

Returns history record.
$action can be 'current', 'prev' or 'next'

example: get_hist('prev', 10) returns record from 10 entries back

returned records are of the format ( $string, \@args, \%props)

=item B<list()>

lists all strings in history as array ref -- does not output args nor props

=item B<del($offset, $length)>

like a splice on the history, without arguments deletes last entry

=item B<set_prop($prop_name, $value, $index)>

Sets property $prop_name to value $value for the history record with
the index $index. If index is omitted sets property for last entry.

=item B<get_prop($prop_name, $index)>

Returns the value of property $prop_name for the record with index $index.
If index is omitted sets property for last entry.

=item B<search()>

TODO - search on string or property

=item B<show()>

TODO - should print hist nicely formatted

=item B<add_dir($dir)>

Add a dir to directory history.

=item B<get_dir($action)>

Get a dir from directory history.
Action can be 'forw' or 'back'.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::Fish>

L<Zoidberg::Buffer>

L<http://zoidberg.sourceforge.net>

=cut

package Zoidberg::Fish::History;

our $VERSION = '0.2';

use strict;
use IO::File();
use Data::Dumper;
use Storable qw/dclone/;

use base 'Zoidberg::Fish';

# @{$self->{data}{hist}} = [ [command, \@_, \%prop], .. ]
# whereby @_ is the last entered set for this command

sub init {
	my $self = shift;
	$self->{data} = {
		'hist' => [ [[''], [], {}] ],
		'hist_p' => -1,
		'dir_hist' => {
			'next' => [''],
			'prev' => [''],
		},
	};
	#print Dumper($self->{data}{hist});
	$self->open_log;
	#print Dumper($self->{data}{hist});
}

sub open_log {
	my $self = shift;
	if ($self->{config}{hist_file} && -s $self->{config}{hist_file}) {
		open IN, $self->{config}{hist_file} || die "Could not open hist file";
		@{$self->{data}{hist}} = map {eval($_)} reverse (<IN>);
		close IN;
		if ($@) { $self->parent->print("while reading hist: $@", 'error'); }
	}

	if ($self->{config}{hist_file}) { $self->{log} = IO::File->new('>>'.$self->{config}{hist_file}) || die $!; }
	else { $self->print("No hist file found.", 'warning'); }
}

sub close_log {
	my $self = shift;
	if (ref($self->{log})) { $self->{log}->close; }
	if ($self->{config}{hist_file}) {
		open OUT, '>'.$self->{config}{hist_file} || die "Could not open hist file";
		print OUT map {$self->serialize($_)."\n"} grep {$_->[0]} reverse @{$self->{data}{hist}};
		close OUT;
	}
	else { $self->print("No hist file found.", 'warning'); }
}

sub serialize { # recursive
	my $self = shift;
	my $ding = shift;
	if (ref($ding) eq 'ARRAY') {
		return '['.join(', ', map {$self->serialize($_)} @{$ding}).']';
	}
	elsif (ref($ding) eq 'HASH') {
		return '{'.join(', ', map {$_.'=>'.$self->serialize($ding->{$_})} keys %{$ding}).'}';
	}
	else {
		$ding =~ s/([\'\\])/\\$1/g;
		return '\''.$ding.'\'';
	}
}

sub add {
	my $self = shift; #print "debug hist got: ".Dumper(\@_);
	if (my $ding = shift) {
		my @r = map {/\n/?split("\n", $_):$_} ref($ding) ? @{$ding} : ($ding);
		unless (_arr_eq([@r], $self->{data}{hist}[0][0])) {
			# t for time, r for redundancy
			# dclone just to be sure
			my $record = dclone([ [@r], [@_], { 't' => time, 'r' => 1, } ]);
			$self->broadcast_event("history_add",$record);

			unshift @{$self->{data}{hist}}, $record;
			my $max = $self->{config}{max_hist} || 100;
			if ($#{$self->{data}{hist}} > $max) { pop @{$self->{data}{hist}}; }
			$self->{log}->print($self->serialize($self->{data}{hist}[0]));
		}
		else {
			$self->{data}{hist}[0][1] = [@_];
			$self->{data}{hist}[0][2]{r}++;
		}
	} #else { print "debug got empty string\n"; }
	$self->{data}{hist_p} = -1; # reset history pointer
}

sub _arr_eq {
	my $ref1 = pop;
	my $ref2 = pop;
	unless ($#{$ref1} == $#{$ref2}) { return 0; }
	foreach my $i (0..$#{$ref1}) { unless ($ref1->[$i] eq $ref2->[$i]) { return 0; } }
	return 1;
}

sub get {
	# arg: undef or "current" || "prev" || "next"
	# arg: int next or prev
	my $self = shift;
	my $act = shift;
	my $int = shift || 1;
	#print "debug: point: -$self->{data}{hist_p}- int -$int-\n";
	if ($act eq "prev") {
		if ( ($self->{data}{hist_p} + $int) <= $#{$self->{data}{hist}}) { $self->{data}{hist_p} += $int; }
		else {
			if ($self->{data}{hist_p} == $#{$self->{data}{hist}}) {$self->parent->Buffer->bell;}
			$self->{data}{hist_p} = $#{$self->{data}{hist}};
		}
	}
	elsif ($act eq "next") {
		if ($self->{data}{hist_p} - $int >= -1) { $self->{data}{hist_p} -= $int; }
		else {
			if ($self->{data}{hist_p} == -1) {$self->parent->Buffer->bell;}
			$self->{data}{hist_p} = -1;
		}
	}
	#print "debug: point: -$self->{data}{hist_p}-\n";
	my @record = ($self->{data}{hist_p} >= 0) ? @{$self->{data}{hist}[$self->{data}{hist_p}]} : ([''], [], {});
	return @record;
}

sub list {
	my $self = shift;
	return [ map {join("\n", $_->[0])} @{$self->{data}{hist}} ] ;
}

sub del {
	my $self = shift;
	my $off = shift || 0;
	my $len = shift || 1;
	my @removed = splice(@{$self->{data}{hist}}, $off, $len);
	$self->broadcast_event("history_delete", @removed);
}

sub set_prop {
	my $self = shift;
	my $prop = shift;
	my $value = shift;
	my $index = shift || 0;
	$self->{data}{hist}[$index][2]{$prop} = $value;
}

sub get_prop {
	my $self = shift;
	my $prop = shift;
	my $index = shift || 0;
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
	$self->close_log;
}

1;
__END__

=head1 NAME

Zoidberg::Fish::History - History plugin for the Zoidberg shell

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

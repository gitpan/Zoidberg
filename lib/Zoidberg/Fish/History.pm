package Zoidberg::Fish::History;

our $VERSION = '0.41';

use strict;
use IO::File();
use Data::Dumper;
use Storable qw/dclone/;
use Zoidberg::Utils qw/message/;
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
	if ($self->{config}{log_file} && -s $self->{config}{log_file}) {
		open IN, $self->{config}{log_file} || die "Could not open log file";
		@{$self->{data}{hist}} = map {
			m/-\s*\[\s*(\d+)\s*,\s*hist\s*,\s*"(.*?)"\s*\]\s*$/;
			[
				[ split /(?<!\\)\\n/, $2 ], # FIXME: escaping ain't right
				[],
				{ 't' => $1 },
			]
		} reverse (<IN>); # FIXME 'hist' type flexible
		close IN;
	}

	if ($self->{config}{log_file}) {
		$self->{log} = IO::File->new('>>'.$self->{config}{log_file}) || die $!;
	}
	else { message "No hist log found." }
}

sub close_log {
	my $self = shift;
	if (ref($self->{log})) { $self->{log}->close; }
	if ($self->{config}{log_file}) {
		open OUT, '>'.$self->{config}{log_file} || die "Could not open hist file";
		print OUT "# This file is used by zoid(1)\n";
		print OUT map {$self->log_record($_)."\n"} grep {@{$_->[0]}} reverse @{$self->{data}{hist}};
		close OUT;
	}
	else { message "No hist log found." }
}

sub log_record {
	my ($self, $ref, $type) = (@_, 'hist');
	"- [ $ref->[2]{t}, $type, \"".join('\n', @{$ref->[0]}).'" ]';
}

sub add {
	my $self = shift; #print "debug hist got: ".Dumper(\@_);
	return if $self->{parent}{settings}{no_hist}; # when hist becomes log, do this for default/hist type only
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
			$self->{log}->print($self->log_record($self->{data}{hist}[0])."\n");
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
	my @record = ($self->{data}{hist_p} >= 0) 
		? @{$self->{data}{hist}[$self->{data}{hist_p}]} 
		: ([''], [], {});
	return @{dclone \@record};
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
	my $str = shift;
	for (@{$self->{data}{hist}}) {
		foreach my $l (@{$_->[0]}) {
			return $_->[0] if $l =~ /$str/;
        	}
    	}
	return;
}

sub show {
	my $self = shift;
}

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

=head1 DESCRIPTION

This module provides a history log for the
zoidberg shell.

FIXME OUT OF DATE DOC !

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

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Fish>, L<Zoidberg::Buffer>,
L<http://zoidberg.sourceforge.net>

=cut

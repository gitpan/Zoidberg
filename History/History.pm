package Zoidberg::History;

our $VERSION = '0.1';

use strict;
use base 'Zoidberg::Fish';

push @Zoidberg::History::ISA, ("Zoidberg::PdParse");

# TODO
# dir history
# pattern recognizion
# lijkt bug te zijn met opslag -- of mn zoid gaat gewoon te vaak dood

# @{$self->{cache}{hist}} = [ [utime, command, redundancy, @_], .. ] # @_ is the last entered set for this command

push @Zoidberg::History::ISA, 'Zoidberg::PdParse';

sub init {
	my $self = shift;
	if ($self->{config}{hist_file} && -s $self->{config}{hist_file}) {
		#print "debug : reading history\n";
		$self->{cache} = $self->pd_read($self->{config}{hist_file});
		$self->{cache}{hist_p} = 0;
	}
	else {
		$self->{cache}{hist} = [ [undef, '', 0] ];
		$self->{cache}{hist_p} = 0;
		$self->{cache}{dir_hist}{futr} = [];
		$self->{cache}{dir_hist}{past} = [];
	}

#	if ($self->{config}{use_kirl}) {
#		use Zoidberg::History::Kirl;
#		$self->{kirl} = Zoidberg::History::Kirl->new($self->{config}{kirl_config});
#	}
	return 1;
}

sub add_history {
	my $self = shift;
	my $ding = shift;
	$ding =~ s/([\'\"])/\\$1/g;		#escape quotes #" save markup :(
	$ding = '\''.$ding.'\'';	#put on safety quotes
	#print "debug: add hist ding is: $ding ,  max hist: ".$self->{config}{max_hist}."\n";
	if ( $ding && ($ding ne $self->{cache}{hist}[1][1]) ) {
        my $ent = [time, $ding, 1, @_];
        $self->broadcast_event("history_add",$ent);
		$self->{cache}{hist}[0] = $ent;
		unshift @{$self->{cache}{hist}}, [undef, '', 0];
		if ($#{$self->{cache}{hist}} > $self->{config}{max_hist}) { pop @{$self->{cache}{hist}}; }
	}
	elsif ($ding eq $self->{cache}{hist}[1][1]) { $self->{cache}{hist}[1] = [ @{$self->{cache}{hist}[1]}[0..1], ++$self->{cache}{hist}[1][2], @_]; }
	$self->{cache}{hist_p} = 0; # reset history pointer
}

sub get_hist {	# arg undef -> @hist | "back" -> $last | "forw" -> $next / "current" -> $current
	my $self = shift;
	my $act = shift || return map {
		my $dus = $_->[1]; $dus =~ s/(^\'|\'$)//g; $dus =~ s/\\([\'\"])/$1/g; $dus;
	} @{$self->{cache}{hist}}[1..$#{$self->{cache}{hist}}-1] ; #" # if no arg return array
	my $int = shift || 1;
	if ($act eq "back") {	# one or more back in hist
		if ($self->{cache}{hist_p} + $int <= $#{$self->{cache}{hist}}) { $self->{cache}{hist_p} += $int; }
	}
	elsif ($act eq "forw") {	# one or more forward in hist
		if ($self->{cache}{hist_p} - $int >= 0) { $self->{cache}{hist_p} -= $int; }
	}
	my @result = @{$self->{cache}{hist}[$self->{cache}{hist_p}]};
	$result[1] =~ s/(^\'|\'$)//g;
	$result[1] =~ s/\\([\'\"])/$1/g; #get rid of safety quotes #" save markup :(
	return @result;
}

sub list_hist {
	my $self = shift;
	return [ map {
		my $dus = $_->[1]; $dus =~ s/(^\'|\'$)//g; $dus =~ s/\\([\'\"])/$1/g; $dus;
	} @{$self->{cache}{hist}}[1..$#{$self->{cache}{hist}}] ] ;
}

sub del_one_hist {
	my $self = shift;
	my $int = shift || 1;
	$self->broadcast_event("history_delete",splice(@{$self->{cache}{hist}}, $int, 1));
}

sub suggest {
	my $self = shift;
	if ($self->{config}{use_kirl}) {
		# vindt een na laatste die is uitgevoerd
		my $input = [ undef, $ENV{PWD}];
		for (my $i = 0; $i <= $#{$self->{cache}{hist}}; $i++) {
			if ($self->{cache}{hist}[$i][4]) {
				$input = [ $self->{cache}{hist}[$i][1], $ENV{PWD}];
				last;
			}
		}
		my $string = $self->{kirl}->suggestion($input);
		$string =~ s/(^\'|\'$)//g;
		$string =~ s/\\([\'\"])/$1/g; #get rid of safety quotes #" save markup :(
		return $string;
	}
	else { return ''; }
}

sub set_exec_last {
	my $self = shift;
	$self->{cache}{hist}[1][4] = 1;
	if ($self->{config}{use_kirl}) {
		# vindt een na laatste die is uitgevoerd
		my $input = [ undef, $ENV{PWD}];
		for (my $i = 2; $i <= $#{$self->{cache}{hist}}; $i++) {
			if ($self->{cache}{hist}[$i][4]) {
				$input = [ $self->{cache}{hist}[$i][1], $ENV{PWD}];
				last;
			}
		}
		$self->{kirl}->remember($input, $self->{cache}{hist}[1][1]);
	}
}

sub search_hist {
	my $self = shift;
	my $string = shift;
	eval { my $test = 'just a string'; $test =~ /$string/; };
	if ($@) { $self->parent->print($@); }
	else { return join("\n", map { join("\t", @{$_}[0..1]) } grep {$_->[1] =~ /$string/} reverse @{$self->{cache}{hist}}); }
}

sub show_hist {
	my $self = shift;
	return join("\n", map { join("\t", @{$_}[0..1]) } reverse @{$self->{cache}{hist}}[1..$#{$self->{cache}{hist}}-1]); # vunzig :))
}

##################
#### dir hist ####
##################

sub add_dir_hist {
	my $self = shift;
	my $dir = shift || $ENV{PWD};
	push @{$self->{cache}{dir_hist}{past}}, $dir;
}

sub get_dir_hist {
	my $self = shift;
	my $act = shift;
	if ($act eq "forw") {
		if (@{$self->{cache}{dir_hist}{futr}}) {
			push @{$self->{cache}{dir_hist}{push}}, $ENV{PWD};
			return pop @{$self->{cache}{dir_hist}{futr}};
		}
		else { return ''; }
	}
	elsif ($act eq "back") {
		if (@{$self->{cache}{dir_hist}{past}}) {
			push @{$self->{cache}{dir_hist}{futr}}, $ENV{PWD};
			return pop @{$self->{cache}{dir_hist}{past}};
		}
		else { return ''; }
	}
}


##############
#### rest ####
##############

sub round_up {
	my $self = shift;
	if ($self->{config}{hist_file}) {
		unless ($self->pd_write($self->{config}{hist_file}, $self->{cache})) {
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

=head1 METHODS

=head2 add_history($string, @_)

  Stores arguments in history

=head2 get_hist($action, $int)

  Returns history record.
  $action can be 'back' or 'forw'
  example: get_hist('back', 10) returns record from 10 entries back
  if action is ommitted a array of all entries is returned

=head2 del_one_hist()

  Deletes last stored record -- lousy hack

=head2 search_hist($regex)

  Returns records matching $regex

=head2 show_hist()

  Returns all records as text

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

http://zoidberg.sourceforge.net
.
=cut

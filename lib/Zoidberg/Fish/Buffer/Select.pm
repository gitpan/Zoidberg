package Zoidberg::Fish::Buffer::Select;
use Term::ANSIColor;

our $VERSION = '0.3b';

use strict;
use base 'Zoidberg::Fish::Buffer';
use Data::Dumper;

sub _switch_on {
	$_[0]->{_mark} = [ @{$_[0]->{pos}} ];
	if ($_[1]) { $_[0]->_do_key($_[1]); }
}

sub _switch_off { delete $_[0]->{_mark}; }

sub default {
	my $self = shift;
	my $key = shift;
	$self->rub_out;
	$self->_do_key($key);
}

sub rub_out {
	my $self = shift;
	my ($a, $b) = $self->_sort_mark_and_pos;
	my $diff = 0;
	if ($a->[1] == $b->[1]) { $diff = $b->[0] - $a->[0] + 1; }
	else {
		$diff = length($self->{fb}[$a->[1]]) - $a->[0];
		for (1..$a->[1] - $b->[1]) {
			$diff += length($self->{fb}[$a->[1]+$_])
		}
		$diff += length($self->{fb}[$b->[1]]) - $b->[0];
	}
	$self->{pos} = [ @{$a} ];
	$self->switch_modus('insert');
	$self->rub_out($diff);
}

sub _sort_mark_and_pos {
	my $self = shift;
	return sort {
		if ($a->[1] == $b->[1]) { $a->[0] <=> $b->[0] }
		else { $a->[1] <=> $b->[1] }
	} ($self->{pos}, $self->{_mark});
}

sub copy {}

sub paste {}

sub cut {
	$_[0]->copy;
	$_[0]->rub_out;
}

sub highlight { # this belongs in a string util module or something !!!
	my $self = shift;

	my @r = @{$self->{fb}};

	# do select highlighting
	my ($a, $b) = $self->_sort_mark_and_pos;
	my $diff = 0;
	if ($a->[1] == $b->[1]) {
		unless ($a->[0] == $b->[0]) {
			my $str1 = substr($r[$a->[1]], 0, $a->[0], '');
			my $str2 = substr($r[$a->[1]], 0, ($b->[0] - $a->[0]), '');
			$r[$a->[1]] = $str1.color('reverse').$str2.color('reset').$r[$a->[1]];
		}
	}
	else {}

	# display hack
	if ($self->{config}{magick_char}) { map {s/\xA3/$self->{config}{magick_char}/g; $_} @r; }

	return @r;
}

1;

__END__

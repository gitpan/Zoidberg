package Zoidberg::Fish::Buffer::Insert::MultiLine;

our $VERSION = '0.42';

use strict;
use base 'Zoidberg::Fish::Buffer::Insert';

sub k_return {
	my $self = shift;
	#$self->insert_string("\n");
	my $string = $self->{fb}[$self->{pos}[1]] ;
	$self->{fb}[$self->{pos}[1]] = substr($string, 0, $self->{pos}[0], ""); # return first half of string keep second half
	$self->{pos}[1]++;
	splice(@{$self->{fb}}, $self->{pos}[1], 0, $string); # copy second half to new line
	$self->{pos}[0] = 0;
}

sub k_ctrl_d {
	my $self = shift;
	unless (join('', @{$self->{fb}}) =~ /^\s*$/) { $self->{continu} = 0; }
	else {
		$self->reset;
		print "\n";
		$self->respawn;
	}
}

sub k_tab {
	my $self = shift;
	$self->insert_string($self->{tab_string});
}


1;

__END__

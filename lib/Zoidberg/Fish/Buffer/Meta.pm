package Zoidberg::Fish::Buffer::Meta;
use Storable qw/dclone/;

our $VERSION = '0.3a_pre1';

use strict;
use base 'Zoidberg::Fish::Buffer';

sub switch_info { $_[0]->{config}{info} = $_[0]->{config}{info} ? 0 : 1 ; }

sub default {
	my $self = shift;
	$self->{_meta_fb} .= shift;
}

sub new_buffer {
	my $self = shift;
	push @{$self->{_saved_buff}}, $self->_pack_record;
	$self->_part_reset;
}

sub rotate_buffer {
	my $self = shift;
	push @{$self->{_saved_buff}}, $self->_pack_record;
	$self->_unpack_record(shift @{$self->{_saved_buff}});
}

sub _part_reset {
	my $self = shift;
	$self->{pos} = [0, 0];
	$self->{tab_exp_back} = [ ["", ""] ];
	$self->{fb} = [''];
	$self->{state} = 'idle';
	$self->{options} = {};
}

sub _pack_record {
	my $self = shift;
	return [ dclone($self->{fb}), dclone($self->{tab_exp_back}), dclone($self->{pos}), dclone($self->{options})];
}

sub _unpack_record {
	my $self = shift;
	my $rec = shift;
	($self->{fb}, $self->{tab_exp_back}, $self->{pos}, $self->{options}) = @{$rec};
}

1;

__END__


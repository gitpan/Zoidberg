package Zoidberg::Fish::Buffer::Insert;

our $VERSION = '0.2';

use strict;
use base 'Zoidberg::Fish::Buffer';

sub k_backspace { # TODO clean up -- make rub_out multiline
	my $self = shift;
	if (($self->{pos}[0] == 0) && ($self->{pos}[1] > 0)) {		# remove line break
		$self->move_left;
		$self->{fb}[$self->{pos}[1]] .= $self->{fb}[$self->{pos}[1]+1];
		splice(@{$self->{fb}}, $self->{pos}[1]+1, 1);
	}
	elsif ($_[0] eq 'fast') {
		while ( (substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0]-1, 1) ne ' ') && ($self->{pos}[0] > 0)) {
			$self->rub_out(-1);
		}
		$self->rub_out(-1);
	}
	elsif ($self->{pos}[0] > 0) {
		my $exp_length = length($self->{tab_exp_back}[-1][0]);
		#print "debug: ".Dumper($self->{tab_exp_back});
		if ($self->{tab_exp_back}[-1][0] && (substr($self->{fb}[$self->{pos}[1]], ($self->{pos}[0] - $exp_length), $exp_length) eq $self->{tab_exp_back}[-1][0])) {
			# is string in front of cursor matches last tab_exp - replace with old buffer
			for (1..$exp_length) { $self->rub_out(-1); }
			$self->insert_string($self->{tab_exp_back}[-1][1]);
			pop @{$self->{tab_exp_back}};
		}
		else {
			my $i = 1;
			my $tab_length = length($self->{tab_string});

			if (substr($self->{fb}[$self->{pos}[1]], ($self->{pos}[0] - $tab_length), $tab_length) eq $self->{tab_string}) {
				$i = $tab_length;	# substring in front of cursor matches tab string, delete it
			}

			for (1..$i) {
				$self->rub_out(-1);
			}
		}
	}
	else { $self->bell; }
}

sub k_return {
	my $self = shift;
	unless (join('', @{$self->{fb}}) =~ /^\s*$/) { $self->{continu} = 0; }
	else {
		$self->reset;
		print "\n";
		$self->respawn;
	}
}

sub k_insert {} # overwrite

sub k_page_up { $_[0]->history_get('prev', 10); }

sub k_page_down { $_[0]->history_get('next', 10); }

sub k_esc { $_[0]->switch_modus('meta'); }


1;

__END__

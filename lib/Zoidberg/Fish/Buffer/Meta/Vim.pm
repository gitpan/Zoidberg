package Zoidberg::Fish::Buffer::Meta::Vim;

our $VERSION = '0.40';

use strict;
use Zoidberg::Utils qw/debug/;
use base 'Zoidberg::Fish::Buffer::Meta';

sub _switch_on { $_[0]->{_vim_meta_cmd} = '' } 

sub _do_key {
	my ($self, $key) = @_;
	if ($key eq 'esc') { $self->{_vim_meta_cmd} = '' }
	else {
		$self->{_vim_meta_cmd} .= $key;
		$self->_try_it;
	}
}

sub _try_it { # / <count>? ( <cmd> (<cmd> | <count>? <motion>) | <motion> /
	my $self = shift;
	return undef unless $self->{_vim_meta_cmd} =~ /^(\d*)(.)(.*)(?<!\d)$/;
	my ($cnt, $s1, $s2) = ($1 || 1, $2, $3);
	# my $modus = $self->{current_modus};
	if ($cnt == 1 and exists $self->{bindings}{$self->{current_modus}}{$s1}) {
		debug "gonna do meta key '$s1'";
		$self->{bindings}{$self->{current_modus}}{$s1}->($cnt, $s2);
	}
	elsif (exists $self->{bindings}{$self->{current_modus}}{vim_motions}{$s1}) {
		debug "gonna do vim_motions key '$s1'";
		$self->{bindings}{$self->{current_modus}}{vim_motions}{$s1}->($cnt);
	}
	elsif (exists $self->{bindings}{$self->{current_modus}}{vim_commands}{$s1}) {
		return undef unless $s2;
		debug "gonna do vim_commands '$s1$s2'";
		$self->{bindings}{$self->{current_modus}}{vim_commands}{$s1}->($cnt, $s2);
	}
	else { $self->bell }
	$self->{_vim_meta_cmd} = '';
	# $self->switch_modus() unless $self->{current_modus} ne $modus;
	return 1;
}

sub delete { print "\ndeleting stuff\n" }

sub replace { print "\nreplacing stuff\n" }

1;

package Zoidberg::Fish::ReadLine;

our $VERSION = '0.53';

use strict;
use vars qw/$AUTOLOAD $PS1 $PS2/;
use Carp;
use Zoidberg::Fish;
use Zoidberg::Utils qw/:error message debug/; # don't import output cause RL:Z has it's own

our @ISA = qw/Zoidberg::Fish/;

eval 'use Env::PS1 qw/$PS1 $PS2 $RPS1/; 1'
	or eval 'use Env qw/$PS1 $PS2 $RPS1/; 1'
		or ( our ($PS1, $PS2, $RPS1) = ("zoid-$Zoidberg::VERSION> ", "> ", undef) );

sub init {
	my $self = shift;

	# let's see what we have available
	unless ($ENV{PERL_RL} and $ENV{PERL_RL} !~ /zoid/i) {
		eval 'require Term::ReadLine::Zoid';
		unless ($@) { # load RL zoid
			$ENV{PERL_RL} = 'Zoid' unless defined $ENV{PERL_RL};
			push @ISA, 'Term::ReadLine::Zoid';
			$self->_init('zoid');
			@$self{'rl', 'rl_z'} = ($self, 1);
			$$self{default_mode} = __PACKAGE__;
			$$self{config}{PS2} = \$PS2;
			$$self{config}{RPS1} = \$RPS1;
			# FIXME support RL:Z shell() option
		}
		else {
			debug $@;
		}
	}

	unless ($$self{rl_z}) { # load other RL
		eval 'require Term::ReadLine';
		error 'No ReadLine available' if $@;
		$$self{rl} = Term::ReadLine->new('zoid');
		$$self{rl_z} = 0;
		message 'Using '.$$self{rl}->ReadLine(). " for input\n"
			. 'we suggest you use Term::ReadLine::Zoid'; # officially nag-ware now :)
	}
	## hook history
	if (my ($thing) = grep { $$self{rl}->can($_) } qw/SetHistory AddHistory addhistory/) {
		my @hist = $self->call('read_history');
		if (@hist) {
			if ($thing eq 'SetHistory') { $$self{rl}->SetHistory(@hist) }
			else { $$self{rl}->$thing($_) for @hist }
		}
	}

	## completion
	my $compl = $$self{rl_z} ? 'complete' : 'completion_function' ;
	$$self{rl}->Attribs->{completion_function} = sub { return $self->call($compl, @_) };
}

sub wrap_rl {
	my ($self, $prompt, $preput) = @_;
	$prompt = $$self{rl_z} ? \$PS1 : $PS1 unless $prompt;
	my $line;
	{
		local $SIG{TSTP} = 'DEFAULT' unless $$self{parent}{settings}{login};
		$line = $$self{rl}->readline($prompt, $preput);
	}
	# TODO continue() support
	return $line;
}

sub beat {
	$_[0]{parent}->reap_jobs() if $_[0]{settings}{notify};
	$_[0]->broadcast('beat');
}

sub AUTOLOAD {
	my $self = shift;
	$AUTOLOAD =~ s/^.*:://;
	return if $AUTOLOAD eq 'DESTROY';
	if ( $$self{rl}->can( $AUTOLOAD ) ) { $$self{rl}->$AUTOLOAD(@_) }
	else { croak "No such method Zoidberg::Fish::ReadLine::$AUTOLOAD()" }
}

1;

__END__

=head1 NAME

Zoidberg::Fish::ReadLine - readline glue for zoid

=head1 SYNOPSIS

=head1 DESCRIPTION

descriptve text

=head1 EXPORT

None by default.

=head1 METHODS

=over 4

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Fish>,
L<Term::ReadLine::Zoid>,
L<Term::ReadLine>

=cut


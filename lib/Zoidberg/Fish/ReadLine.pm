package Zoidberg::Fish::ReadLine;

our $VERSION = '0.90';

use strict;
use vars qw/$AUTOLOAD $PS1 $PS2/;
use Zoidberg::Fish;
use Zoidberg::Utils
	qw/:error message debug/; # T:RL:Zoid also has output()

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
			$ENV{PERL_RL} =~ /^(\S+)/;
			push @ISA, 'Term::ReadLine::'.$1; # could be a subclass of T:RL:Zoid
			$self->_init('zoid');
			@$self{'rl', 'rl_z'} = ($self, 1);
			$$self{config}{PS2} = \$PS2;
			$$self{config}{RPS1} = \$RPS1;
			# FIXME support RL:Z shell() option
			# FIXME what if config/PS1 was allready set to a string ?
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
		my @hist = $$self{shell}->builtin('history');
		if (@hist) {
			if ($thing eq 'SetHistory') { $$self{rl}->SetHistory(reverse @hist) }
			else { $$self{rl}->$thing($_) for @hist }
		}
	}

	## completion
	my $compl = $$self{rl_z} ? 'complete' : 'completion_function' ;
	$$self{rl}->Attribs->{completion_function} = sub { return $$self{shell}->builtin($compl, @_) };

	## Env::PS1
	# TODO in %Env::PS1::map
	# \m  Current mode, '-' if default
	# \M "general status string" in prompt to be used by mode plugins
	# \j  The number of jobs currently managed by the application.
	# \v  The version of the application.
	# \V  The release number of the application, version + patchelvel
}

sub wrap_rl {
	my ($self, $prompt, $preput, $cont) = @_;
	$prompt = $$self{rl_z} ? \$PS1 : $PS1 unless $prompt;
	my $line;
	{
		local $SIG{TSTP} = 'DEFAULT' unless $$self{shell}{settings}{login};
		$line = $$self{rl}->readline($prompt, $preput);
	}
	$$self{last_line} = $line;
	Zoidberg::Utils::output($line);
}

sub wrap_rl_more {
	my ($self, $prompt, $preput) = @_;
	my $line;
	if ($$self{rl_z}) { $line = $self->continue() }
	else { $line = $$self{last_line} . $self->wrap_rl($prompt, $preput) }
	$$self{last_line} = $line;
	Zoidberg::Utils::output($line);
}

sub beat {
	$_[0]{shell}->reap_jobs() if $_[0]{settings}{notify};
	$_[0]->broadcast('beat');
}

sub select {
	my ($self, @items) = @_;
	@items = @{$items[0]} if ref $items[0];
	my $len = length scalar @items;
	Zoidberg::Utils::message(
		[map { sprintf("%${len}u) ", $_ + 1) . $items[$_] }  0 .. $#items] );
	SELECT_ASK:
	my $re = $self->ask('#? ');
	return undef unless $re;
	unless ($re =~ /^\d+([,\s]+\d+)*$/) {
		complain 'Invalid input: '.$re;
		goto SELECT_ASK;
	}
	my @re = map $items[$_-1], split /\D+/, $re;
	if (@re > 1 and ! wantarray) {
		complain 'Please select just one item';
		goto SELECT_ASK;
	}
	Zoidberg::Utils::output @re;
}

our $ERROR_CALLER;

sub AUTOLOAD {
	my $self = shift;
	$AUTOLOAD =~ s/^.*:://;
	return if $AUTOLOAD eq 'DESTROY';
	if ( $$self{rl}->can( $AUTOLOAD ) ) { $$self{rl}->$AUTOLOAD(@_) }
	else {
		local $ERROR_CALLER = 1;
		error "No such method Zoidberg::Fish::ReadLine::$AUTOLOAD()";
	}
}

1;

__END__

=head1 NAME

Zoidberg::Fish::ReadLine - Readline glue for zoid

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


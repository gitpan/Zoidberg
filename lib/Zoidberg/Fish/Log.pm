package Zoidberg::Fish::Log;

our $VERSION = '0.53';

use strict;
use Zoidberg::Utils qw/:default abs_path/;
use base 'Zoidberg::Fish';

sub read_history { # also does some bootstrapping
	my $self = shift;
	$$self{logfh}->close() if ref $$self{logfh};

	my @hist;
	my $file = abs_path( $$self{config}{logfile} );
	unless ($file) {
		complain 'No log file defined, can\'t read history';
		return;
	}
	elsif (-e $file and ! -r _) {
		complain 'Log file not readable, can\'t read history';
		return;
	}
	elsif (-s _) {
		debug "Going to read $file";
		open IN, $file || error 'Could not open log file !?';
		@hist = grep { $_ } map {
			m/-\s*\[\s*\d+\s*,\s*hist\s*,\s*"(.*?)"\s*\]\s*$/
			? $1 : undef
		} reverse (<IN>);
		close IN;
	}

	if ( $$self{logfh} = IO::File->new(">>$file") ) {
		$self->register_event('cmd') unless $$self{_r_cmd}; # probably interactive here
		$$self{_r_cmd}++;
	}
	else { complain "Log file not writeable, logging disabled" }

	debug 'Found '.scalar(@hist).' log records in '.$file;
	return @hist;
}

sub cmd {
	my ($self, undef,  $cmd) = @_;
	return unless ref $$self{logfh};
	$$self{logfh}->print('- [ '.time().", hist, \"$cmd\" ]\n")
		unless $$self{config}{no_duplicates} and $cmd eq $$self{prev_cmd};
	$$self{prev_cmd} = $cmd;
}

sub round_up {
	my $self = shift;

	return unless ref $$self{logfh};
	$$self{logfh}->close();

	return unless $$self{config}{maxlines};
	my $file = abs_path( $$self{config}{logfile} );

	open IN, $file or error "Could not open hist file";
	my @lines = (reverse (<IN>))[0 .. $$self{config}{maxlines}];
	close IN or error "Could not read hist file";

	open OUT, ">$file" or error "Could not open hist file";
	print OUT reverse @lines;
	close OUT;
}

1;

__END__

=head1 NAME

Zoidberg::Fish::Log - History and log plugin for Zoidberg

=head1 SYNOPSIS

This module is a Zoidberg plugin, see Zoidberg::Fish for details.

=head1 DESCRIPTION

descriptve text

=head1 EXPORT

None by default.

=head1 METHODS

=over 4

=item C<new()>

Simple constructor

=back

=head1 AUTHOR

Jaap Karssenberg (Pardus) E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

=cut


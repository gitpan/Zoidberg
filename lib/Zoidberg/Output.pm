
package Zoidberg::Output;

our $VERSION = '0.40';

use strict;
use Data::Dumper;
use POSIX qw/floor ceil/;
use Term::ANSIColor;

our @ansi_colors = qw/
	clear rest bold underline underscore blink
	black red green yellow blue magenta cyan white
	on_black on_red on_green on_yellow on_blue
	on_magenta on_cyan on_white
/;

sub output { typed_output('output', @_) }

sub message { typed_output('message', @_) }

sub debug {
	my $class = caller;
	no strict 'refs';
	return unless $ENV{ZOIDREF}->{settings}{debug} || ${$class.'::DEBUG'};
	my @caller = caller;
	{
		no strict 'refs';
		@caller = caller(${ $caller[0].'::ERROR_CALLER' }) 
			if ${ $caller[0].'::ERROR_CALLER' };
	}
	my $fh = select STDERR;
	typed_output('debug', "$caller[0]: $caller[2]: ", @_);
	select $fh;
	1;
}

sub complain {
	my $fh = select STDERR;
	unshift @_, $@ if ! @_ && $@;
	return 0 unless @_;
	$ENV{ZOIDREF}->{exec_error} = (@_ > 1) ? \@_ : $_[0];
	typed_output('error', @_);
	select $fh;
	1;
}

sub typed_output {	# TODO term->no_color bitje s{\e.*?m}{}g
	my $type = shift;
	my @dinge = @_;
	return unless @dinge > 0;
#	$self->silent unless -t STDOUT && -t STDIN; # FIXME what about -p ??

	$type = $ENV{ZOIDREF}->{settings}{output}{$type} || $type;
	return 1 if $type eq 'mute';

	my $coloured;
	if (grep {$_ eq $type} @ansi_colors) {
		if ($ENV{ZOIDREF}->{settings}{interactive}) {
			$coloured++;
			print color($type);
		}
	}

	$dinge[-1] .= "\n" unless ref $dinge[-1];
	for (@dinge) {
		unless (ref $_) { print $_ }
		elsif (ref($_) eq 'Zoidberg::Error' and !$$_{debug}) {
			next if $_->{silent}++;
			print $_->stringify(format => 'gnu');
		}
		elsif (
			ref($_) eq 'ARRAY' 
			and ! grep { ref($_) } @$_
		) { output_list(@$_) }
		else { print map {s/^\$VAR1 = //; $_} Dumper $_ }
	}

	print color('reset') if $coloured;
	
	1;
}

sub output_list {
	my (@strings) = @_;
	my $width = ($ENV{ZOIDREF}->Buffer->size)[0]; # FIXME FIXME FIXME hardcoded plugin name

	if (
		   ! $ENV{ZOIDREF}->{settings}{interactive}
		|| ! defined $width
	) {
		print join("\n", @strings), "\n";
		return;
	}

	my $longest = 1;
	for (@strings) { $longest = length $_ if $longest < length $_ }
	$longest += 2; # we want two spaces to saperate coloms
	my $cols = floor($width / $longest);

	if ($cols < 1) { print map "$_\n", @strings }
	else {
		my $rows = ceil @strings / $cols;
		@strings = map {$_.(' 'x($longest - length $_))} @strings;

		foreach my $i (0..$rows-1) {
			print $strings[$_*$rows+$i] for (0..$cols);
			print "\n";
		}
	}
}

sub output_sql { # FIXME FIXME FIXME unmaintained :((
	my $self = $ENV{ZOIDREF}->{zoid};
	my $width = ($self->Buffer->size)[0];
	if (!$self->{settings}{interactive} || !defined $width) { return (print join("\n", map {join(', ', @{$_})} @_)."\n"); }
	my @records = @_;
	my @longest = ();
	@records = map {[map {s/\'/\\\'/g; "'".$_."'"} @{$_}]} @records; # escape quotes + safety quotes
	foreach my $i (0..$#{$records[0]}) {
		map {if (length($_) > $longest[$i]) {$longest[$i] = length($_);} } map {$_->[$i]} @records;
	}
	#print "debug: records: ".Dumper(\@records)." longest: ".Dumper(\@longest);
	my $record_length = 0; # '[' + ']' - ', '
	for (@longest) { $record_length += $_ + 2; } # length (', ') = 2
	if ($record_length <= $width) { # it fits ! => horizontal lay-out
		my $cols = floor($width / ($record_length+2)); # we want two spaces to saperate coloms
		my @strings = ();
		for (@records) {
			my @record = @{$_};
			for (0..$#record-1) { $record[$_] .= ', '.(' 'x($longest[$_] - length($record[$_]))); }
			$record[$#record] .= (' 'x($longest[$#record] - length($record[$#record])));
			if ($cols > 1) { push @strings, "[".join('', @record)."]"; }
			else { print "[".join('', @record)."]\n"; }
		}
		if ($cols > 1) {
			my $rows = ceil(($#strings+1) / $cols);
			foreach my $i (0..$rows-1) {
				for (0..$cols) { print $strings[$_*$rows+$i]."  "; }
				print "\n";
			}
		}
	}
	else { for (@records) { print "[\n  ".join(",\n  ", @{$_})."\n]\n"; } } # vertical lay-out
	return 1;
}

1;

__END__

=head1 NAME

Zoidberg::Output - zoidberg output routines

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

This module provides some routines used by various
Zoidberg modules to output data.

=head1 EXPORT

None by default.

=head1 METHODS

FIXME

=over 4

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


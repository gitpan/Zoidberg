
package Zoidberg::Utils::Output;

our $VERSION = '0.41';

use strict;
use Data::Dumper;
use POSIX qw/floor ceil/;
use Term::ANSIColor;
use Exporter::Tidy
	default => [qw/output message debug complain/],
	other   => [qw/typed_output/];

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
	@_ = ($@) || return 0 unless @_;
	$ENV{ZOIDREF}->{error} = (@_ > 1) ? \@_ : $_[0];
	my $fh = select STDERR;
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
		elsif (ref($_) eq 'Zoidberg::Utils::Error' and !$$_{debug}) {
			next if $_->{printed}++;
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

Zoidberg::Utils::Output - zoidberg output routines

=head1 SYNOPSIS

	use Zoidberg::Utils qw/:output/;

	# use this instead of perlfunc print
	output "get some string outputted";
	output { string => 'or some data struct dumped' };

=head1 DESCRIPTION

This module provides some routines used by various
Zoidberg modules to output data.

Although when working within the Zoidberg framework this module should be used through
the L<Zoidberg::Utils> interface, it also can be used on it's own.

=head1 EXPORT

By default all of the below except C<typed_output>.

=head1 METHODS

=over 4

=item C<output(@_)>

Output a list of possibly mixed data structs as nice as possible.
Lists of plain scalars may be outputted in a multi column list,
more complex data will be dumped using L<Data::Dumper>.

=item C<message(@_)>

Like C<output()> but tags data as a message, in non-interactive mode these may not 
be printed at all.

=item C<debug(@_)>

Like C<output()> tags the data as debug output, will only be printed when in debug mode.
Debug ouput will be printed to STDERR if printed at all.

=item C<complain(@_)>

Like C<output> but intended for error messages, data will be printed to STDERR.
Has some glue for error objects created by L<Zoidberg::Utils::Error>.
Prints C<$@> when no argument is given.

=item C<typed_output($type, @_)>

Method that can be used to define output types that don't fit in the above group.
C<$type> must be a plain string that is used as output 'tag'.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>,
L<http://zoidberg.sourceforge.net>

=cut


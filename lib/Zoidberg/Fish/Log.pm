package Zoidberg::Fish::Log;

our $VERSION = '0.91';

use strict;
use AutoLoader 'AUTOLOAD';
use Zoidberg::Utils qw/:default path getopt/;
use base 'Zoidberg::Fish';

# TODO purge history with some intervals

sub init {
	# TODO in %Env::PS1::map
	# \!  The history number of the next command.
	#	This escape gets replaced by literal '!' while a literal '!' gets replaces by '!!'; this
	#	makes the string a posix compatible prompt, thus it will work if your readline module expects
	# 	a posix prompt.
	# \#  The command number of the next command (like history number, but minus the lines read from
	# 	the history file).
}

sub history { # also does some bootstrapping # FIXME move bootstrapping to init()
	my $self = shift;
	close $$self{logfh} if $$self{logfh};

	my @hist;
	my $file = path( $$self{config}{logfile} );
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
		@hist = map {s/(\\\\)|(\\n)|\\(.)/$1?'\\':$2?"\n":$3/eg; $_} @hist;
	}

	my $fh; # undefined scalar => new anonymous filehandle on open()
	if (open $fh, ">>$file") {
		$$self{logfh} = $fh;
		$self->add_events('cmd') unless $$self{_r_cmd};
		$$self{_r_cmd}++;
	}
	else { complain "Log file not writeable, logging disabled" }

	debug 'Found '.scalar(@hist).' log records in '.$file;
	output \@hist;
}

sub cmd {
	my ($self, undef,  $cmd) = @_;
	return unless $$self{settings}{interactive} and $$self{logfh};
	$cmd =~ s/(["\\])/\\$1/g;
	$cmd =~ s/\n/\\n/g;
	print {$$self{logfh}} '- [ '.time().", hist, \"$cmd\" ]\n"
		unless $$self{config}{no_duplicates} and $cmd eq $$self{prev_cmd};
	$$self{prev_cmd} = $cmd;
}

sub log {
	my ($self, $string, $type) = @_;
	$type ||= 'log';
	return unless $$self{logfh};
	$string =~ s/(["\\])/\\$1/g;
	$string =~ s/\n/\\n/g;
	print {$$self{logfh}} '- [ '.time().', '.$type.", \"$string\" ]\n";
}

sub round_up {
	my $self = shift;

	return unless $$self{logfh};
	close $$self{logfh};

	my $max = defined( $$self{config}{maxlines} )
		? $$self{config}{maxlines} : $ENV{HISTSIZE} ;
	return unless defined $max;
	my $file = path( $$self{config}{logfile} );

	open IN, $file or error "Could not open hist file";
	my @lines = (reverse (<IN>))[0 .. $max-1];
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

This plugin listens to the 'cmd' event and records all
input in the history log.

If multiple instances of zoid are using the same history file
their histories will be merged.
TODO option for more bash like behaviour

In order to use the editor feature of the L<fc> command the module
L<File::Temp> should be installed.

=head1 EXPORT

None by default.

=head1 CONFIG

=over 4

=item loghist

Unless this config is set no commands are recorded.

=item logfile

File to store the history.

=item maxlines

Maximum number of lines in the history. If not set the environment variable
'HISTSIZE' is used. In fact the number of lines can be a bit more then this 
value on run time because the file is not purged after every write.

=item no_duplicates

If set a command will not be saved if it is the same as the previous command.

=back

=head1 COMMANDS

=over 4

=item fc [-r][-e editor] [first[last]]

=item fc -l[-nr] [first[last]]

=item fc -s[old=new][first]

TODO this command doesn't work yet !

=cut

=cut

Command to manipulate the history.

Note that the selection of the editor is not POSIX compliant
but follows bash, if no editor is given using the '-e' option
the environment variables 'FCEDIT' and 'EDITOR' are both checked,
if neither is set, B<vi> is used.
( According to POSIX we should use 'ed' by default and ignore
the 'EDITOR' varaiable. )

=cut

sub fc {
	my $self = shift;
	my ($opt, $args) = getopt 'reverse,r editor,e$ list,l n s @', @_;
	my @replace = split('=', shift(@$args), 2) if $$args[0] =~ /=/;
	error 'usage: fc [options] [old=new] [first [last]]' if @$args > 2;
	
	# get selection
	# TODO -number +number .. needs getopt features
	my ($first, $last) = @$argv;
	if (!$first) { ($first,$last) = $$opt{s} ? (-1, -1) : (-16, -1) }
	elsif (!$last) { $last = -1 }
	# FIXME how to get _our_ hist, not our brothers ?

	if ($$opt{list}) { # list history
		output $$opt{n}
			? [ map @lines ]
			: [ map @lines ] ;
		return;
	}
	
	unless ($$opt{s}) {
		# edit history - editor behaviour consistent with T:RL:Z
		my $editor = $$opt{editor} || $ENV{FCEDIT} || $ENV{EDITOR} || 'vi';
		eval 'require File::Temp' || error 'need File::Temp from CPAN';
		($fh, $file) = File::Temp::tempfile(
			'Zoid_fc_XXXXX', DIR => File::Spec->tmpdir );
		print {$fh} @lines;
		# unless editor error
		# insert new command in history
		#  TODO remove self from history ... posix says so
		# shell new command
		#  TODO inherit environment and redirection from self
	}
}

=item history

Returns the contents of the current history file.

TODO options like the ones for bash's implementation

=item log I<string> I<type>

Adds I<string> to the history file with the current timestamp
and the supplied I<type> tag. The type defaults to "log".
If the type is set to "hist" the entry will become part of the
command history after the history file is read again.

=back

=head1 EVENTS

=over 4

=item read_history

Returns an array with history contents.

=back

=head1 AUTHOR

Jaap Karssenberg (Pardus) E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

=cut


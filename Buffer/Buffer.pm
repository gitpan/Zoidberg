package Zoidberg::Buffer;

use Data::Dumper;
use POSIX qw/floor/;
use Term::ReadKey;
use Term::ANSIScreen qw/:screen :cursor/;
use strict;

use base 'Zoidberg::Fish';

$| = 1;

sub init {
	my $self = shift;
	$self->{parent} = shift;
	$self->{config} = shift;
	#print "debug: buffer config: ".Dumper($self->{config})."\n";
	$self->{tab_string} = $self->{config}{tab_string} || "    ";

	# set default char table
	$self->{char_table}{in_use} = {
		4 => 	"k_ctrld",	# ^D -- left this default value for safety - to be able to exit :)
		10 =>	"k_newl",	# \n -- to be able to submit "b_probe"
	};

	# set probe values
	$self->{probe} = {
		'in_use' => [
			'Normal keybindings',
			["Hard quit", "Ctrl-c", "k_ctrld"],	# TODO ? $SIG{INT}
			["Soft quit", "Ctrl-d", "k_ctrld"],
			["Save buffer", "Ctrl-o", "k_save"],
			["Expand", "tab", "k_expand"],
			["Backspace", "Bcksp", "k_backspc"],
			["Submit", "Return", "k_newl"],
			["Multiline modus switch", "Insert", "multi_line_switch"],
			["Delete", "Del", "k_delete"],
			["Home", "Home", "k_home"],
			["End", "End", "k_end"],
			["History jump back", "Pg Up", "k_pgup"],
			["History jump forward", "Pg dw", "k_pgdw"],
			["Move left", "<- left", "k_moveleft"],
			["Move right", "-> right", "k_moveright"],
			["History one back", "up", "k_hist_back"],
			["History one forward", "down", "k_hist_forw"],
		],
		'multi' => [
			'Keybindings for multiline modus',
			["Submit", "Ctrl-d", "k_m_ctrld"],
			["Tab", "tab", "k_tab"],
			["Newline", "Return", "k_m_newl"],
			["Move up", "up", "k_moveup"],
			["Move down", "down", "k_movedown"]
		]
	};
	if ($self->{config}{probe}) {$self->{probe} = $self->{config}{probe}; } # no merging here - would give rubish

	# this should be a merge !!
	if ($self->{config}{char_table_file} && -s $self->{config}{char_table_file}) { $self->{char_table} = $self->{parent}->pd_read($self->{config}{char_table_file}); }
	else {
		print "No char table found - no file set, file empty or file does not exist ..\n";
		print "To probe chars enter \"Buffer->probe\".\n";
	}
	#print "Debug: ".Dumper($self);
}

sub read {
	my $self = shift;

	$self->{continu} = 1;
	$self->{size} = [(GetTerminalSize())[0,1]];	# width in characters, height in characters
	#print "debug: size ".join(",", @{$self->{size}})."\n";
	$self->{pos} = [0,0]; 	# x,y cursor
	$self->{lines} = 0;
	$self->{last_quest} = ""; # used to make the history more flex
	$self->{tab_exp_back} = ["", ""]; # used to flex up backspace
	$self->{fb} = [""];

#	$self->print_buffer;
	$self->print_prompt;
	while ($self->{continu}) {
		my $key;
		ReadMode("raw");
		while (not defined ($key = ReadKey(0.05))) { } # Timeout 1/20 sec - do people type faster then 20 chars/sec ?
		if (ord($key) == 27) {	# escape char -- moet ook configureerbaar - -zou ook simpeler moeten - twee keer zelfde code is vunzig
			my @dus = (27);
			for (0..2) { push @dus, ord(ReadKey(-1)); } # non blocking
			ReadMode("normal");
			for (0..2) { unless($dus[-1]) {pop @dus;} }
			my $ckey = join("-", @dus);
			#print "debug: ctrl key : $ckey\n";
			if (defined $self->{char_table}{in_use}{$ckey}) {
					my $sub = $self->{char_table}{in_use}{$ckey};
					my @dus = ();
					if ($sub =~ /(\(.*\))\s*$/) {
						@dus = eval($1);
						$sub =~ s/(\(.*\))\s*$//;
					}
					$self->$sub(@dus);
			}
			else {} # do nothing (?)
		}
		elsif (defined $self->{char_table}{in_use}{ord($key)}) {
			#print "Debug: key ".ord($key)."\n";
			ReadMode("normal");
			my $sub = $self->{char_table}{in_use}{ord($key)};
			my @dus = ();
			if ($sub =~ /(\(.*\))\s*$/) {
				@dus = eval($1);
				$sub =~ s/(\(.*\))\s*$//;
			}
			$self->$sub(@dus);
		}
		else { # default
			ReadMode("normal");
			$self->insert_char($key);
		}

		$self->{continu} && $self->print_buffer;
	}
	#print "debug: returning buffer: ".$self->{fb}."\n";
	my $fb = join("\n", @{$self->{fb}});
	$self->{parent}->add_history($fb);
	return $fb;
}

sub insert_char {
	my $self = shift;
	my $key = shift;
	my $loc = $self->{pos}[0];
	if ($self->{pos}[0] > length($self->{fb}[$self->{pos}[1]])) { $loc = length($self->{fb}[$self->{pos}[1]]) }
	$self->{fb}[$self->{pos}[1]] =~ s/^(.{$loc})/$1$key/;
	$self->{pos}[0]++;
}

sub print_prompt {
	my $self = shift;
	unless ($self->{custom_prompt}) {	# else prompt is allready set
		$self->{prompt} = $self->{parent}->prompt->stringify;
		$self->{prompt_lenght} = $self->{parent}->prompt->getLength + 1;
	}
	print locate($self->{size}[1], 0), $self->{prompt}; # locate uses y,x notation !!!
}

sub print_buffer {	# TODO if $lines > heigth of term
	my $self = shift;

	#calculate number of lines and on which line each string starts- first one is special due to prompt length - also calculate spaces
	my @space = ();
	my @start = (0);
	my $lines = floor((length($self->{fb}[0]) + $self->{prompt_lenght})/ $self->{size}[0]);
	$space[0] = (($lines+1) * $self->{size}[0]) - (length($self->{fb}[0]) + $self->{prompt_lenght}) + 1;
	if ($#{$self->{fb}} > 0) {
		for (1 .. $#{$self->{fb}}) {
			my $i = $_;
			$start[$i] = ++$lines;
			my $my_lines = floor(length($self->{fb}[$i])/ $self->{size}[0]);
			$space[$i] = (($my_lines+1) * $self->{size}[0]) - length($self->{fb}[$i]);
			$lines += $my_lines;
		}
	}

	# move previous lines up
	#print locate(0,0), "debug: lines $lines lines in mem  $self->{lines} ";
	my $empty_lines = 0;
	if ($lines < $self->{lines}) {
		$empty_lines =  $self->{lines} - $lines;
		$lines = $self->{lines};
	}
	else {
		for ($self->{lines} .. ($lines-1)) {print locate(reverse(@{$self->{size}})), "\n"; }
		$self->{lines} = $lines;
	}

	#print lines
	my $null_line = $self->{size}[1] - $lines;
	#print locate(0,0), "debug: lines $lines null_line $null_line   ";
	print locate($null_line , $self->{prompt_lenght}), $self->{fb}[0].(" "x$space[0]); # print buffer and overwrite any garbage
	if ($#{$self->{fb}} > 0) {
		for (1 .. $#{$self->{fb}}) {
			my $i = $_;
			print locate( ($null_line + $start[$i]), 0 ),  $self->{fb}[$i].(" "x$space[$i]);
		}
	}

	# print empty lines
	if ($empty_lines) { print locate( ($self->{size}[1] - $empty_lines + 1), 0), " "x($empty_lines * $self->{size}[0]); }

	#set cursor - be aware of line length
	my $c_off = 1;
	if ($self->{pos}[1] == 0) { $c_off = $self->{prompt_lenght}; }
	my $pos = $self->{pos}[0];
	if ($pos > length($self->{fb}[$self->{pos}[1]])) { $pos = length($self->{fb}[$self->{pos}[1]]); }
	my $c_line = floor(($pos + $c_off - 1)/ $self->{size}[0]);
	my $c_x = ($pos + $c_off) % ($self->{size}[0]);
	unless ($c_x) { $c_x = $self->{size}[0]; } # dit is luizige hack - nog s naar kijken
	#print locate (0, 0), "debug: c_line $c_line c_x $c_x pos+c_off ".($pos + $c_off)." size[0] ".($self->{size}[0]);
	print locate( ($null_line + $start[$self->{pos}[1]] + $c_line),  $c_x);
}

sub read_question {
	my $self = shift;
	my $prompt = shift;
	unless (ref($prompt)) {
		$self->{prompt} = $prompt;
		$self->{prompt_lenght} = length($prompt) + 1;
	}
	else {
		$self->{prompt} = $prompt->stringify;
		$self->{prompt_lenght} = $prompt->getLength + 1;
	}
	$self->{custom_prompt} = 1;
	my $answer = $self->read;
	$self->{custom_prompt} = 0;
	return $answer;
}

sub k_delete {
	my $self = shift;
	if ($self->{pos}[0] >= length($self->{fb}[$self->{pos}[1]])) {
		if ($self->{pos}[1] < $#{$self->{fb}}) { 		# remove line break
			$self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]);
			$self->{fb}[$self->{pos}[1]] .= $self->{fb}[$self->{pos}[1]+1];
			splice(@{$self->{fb}}, $self->{pos}[1]+1, 1);
		}
	}
	else { substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0], 1, ""); }
}

sub k_home {
	my $self = shift;
	$self->{pos}[0] = 0;
}

sub k_end {
	my $self = shift;
	$self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]);
}

sub k_moveleft {
	my $self = shift;
	if ($self->{pos}[0] > length($self->{fb}[$self->{pos}[1]])) { $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]) }
	if ($self->{pos}[0] > 0) { $self->{pos}[0]--; }
	elsif ($self->{pos}[1] > 0) {
		$self->{pos}[1]--;
		$self->k_end;
	}
}

sub k_moveright {
	my $self = shift;
	if ($self->{pos}[0] > length($self->{fb}[$self->{pos}[1]])) { $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]) }
	if ($self->{pos}[0] < length($self->{fb}[$self->{pos}[1]])) { $self->{pos}[0]++; }
	elsif ($self->{pos}[1] < $#{$self->{fb}}) {
		$self->{pos}[1]++;
		$self->k_home;
	}
}

sub k_hist_back {
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	unless ($fb eq $self->{last_quest}) { $self->{parent}->add_history($fb); }
	$fb = $self->{parent}->get_hist("back");
	$self->{last_quest} = $fb;
	@{$self->{fb}} = split(/\n/, $fb);
	$self->{pos}[0] = length(@{$self->{fb}}[-1]);
	$self->{pos}[1] = @{$self->{fb}} ? $#{$self->{fb}} : 0;
}

sub k_hist_forw {
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	unless ($fb eq $self->{last_quest}) { $self->{parent}->add_history($fb); }
	$fb = $self->{parent}->get_hist("forw");
	$self->{last_quest} = $fb;
	@{$self->{fb}} = split(/\n/, $fb);
	$self->{pos}[0] = length($self->{fb}[-1]);
	$self->{pos}[1] = @{$self->{fb}} ? $#{$self->{fb}} : 0;
}

sub k_moveup {
	my $self = shift;
	if ($self->{pos}[1] > 0) { $self->{pos}[1]--; }
}

sub k_movedown {
	my $self = shift;
	if ($self->{pos}[1] < $#{$self->{fb}}) { $self->{pos}[1]++; }
}

sub k_ctrld {
	my $self = shift;
	$self->{continu} = 0;
	$self->{fb} = ["_quit"];
	print "\n";
}

sub k_m_ctrld {			# jump out of multi line and submit - ie normal <return>
	my $self = shift;
	$self->multi_line_switch;
	$self->k_newl;
}

#sub k_debug {
#	my $self = shift;
#	print "debug:\n fb: ".Dumper($self->{fb})."pos: ".Dumper($self->{pos});
#}

sub k_tab {
	my $self = shift;
	my @chars = split(//, $self->{tab_string});
	foreach my $char (@chars) { $self->insert_char($char); }
}

sub k_expand {
	my $self = shift;
	#print "debug ".Dumper($self->{parent}->intel->tab_exp($self->{fb}));
	my ($bit, $ref) = $self->{parent}->intel->tab_exp($self->{fb}[$self->{pos}[1]]);
	unless ($ref->[0] eq $self->{fb}[$self->{pos}[1]]) { # create fancy backspace feature
		$self->{tab_exp_back} = [$ref->[0], $self->{fb}[$self->{pos}[1]]];
	}
	$self->{fb}[$self->{pos}[1]] = shift @{$ref};
	$self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]);
	unless ($bit) {
		unless (@{$ref}) { $ref->[0] = "... ???"; }
		print "\n".join("\n", @{$ref})."\n";
		$self->print_prompt;
		$self->print_buffer;
	}
}

sub k_backspc {
	my $self = shift;
	if (($self->{pos}[0] == 0) && ($self->{pos}[1] > 0)) {		# remove line break
		$self->k_moveleft;
		$self->{fb}[$self->{pos}[1]] .= $self->{fb}[$self->{pos}[1]+1];
		splice(@{$self->{fb}}, $self->{pos}[1]+1, 1);
	}
	elsif ($self->{pos}[0] > 0) {
		my $exp_length = length($self->{tab_exp_back}[0]);
		if ($self->{tab_exp_back}[0] && (substr($self->{fb}[$self->{pos}[1]], ($self->{pos}[0] - $exp_length), $exp_length) eq $self->{tab_exp_back}[0])) {
			# is string in front of cursor matches last tab_exp - replace with old buffer
			for (1..$exp_length) {
				$self->k_moveleft;
				$self->k_delete;
			}
			my @chars = split(//, $self->{tab_exp_back}[1]);
			foreach my $char (@chars) { $self->insert_char($char); }
		}
		else {
			my $i = 1;
			my $tab_length = length($self->{tab_string});

			if (substr($self->{fb}[$self->{pos}[1]], ($self->{pos}[0] - $tab_length), $tab_length) eq $self->{tab_string}) {
				$i = $tab_length;	# substring in front of cursor matches tab string, delete it
			}

			for (1..$i) {
				$self->k_moveleft;
				$self->k_delete;
			}
		}
	}
}

sub k_newl {
	my $self = shift;
	$self->{continu} = 0;
	print "\n";
}

sub k_m_newl {
	my $self = shift;
	my $string = $self->{fb}[$self->{pos}[1]] ;
	$self->{fb}[$self->{pos}[1]] = substr($string, 0, $self->{pos}[0], ""); # return first half of string keep second half
	$self->{pos}[1]++;
	splice(@{$self->{fb}}, $self->{pos}[1], 0, $string); # copy second half to new line
	$self->{pos}[0] = 0;
}

sub k_ins {
	my $self = shift;
	# do something fancy
}

sub k_pgup {
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	unless ($fb eq $self->{last_quest}) { $self->{parent}->add_history($fb); }
	for (1..10) { $fb = $self->{parent}->get_hist("back"); }
	$self->{last_quest} = $fb;
	@{$self->{fb}} = split(/\n/, $fb);
	$self->{pos}[0] = length($self->{fb}[-1]);
	$self->{pos}[1] = @{$self->{fb}} ? $#{$self->{fb}} : 0;
}

sub k_pgdw {
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	unless ($fb eq $self->{last_quest}) { $self->{parent}->add_history($fb); }
	for (1..10) { $fb = $self->{parent}->get_hist("forw"); }
	$self->{last_quest} = $fb;
	@{$self->{fb}} = split(/\n/, $fb);
	$self->{pos}[0] = length($self->{fb}[-1]);
	$self->{pos}[1] = @{$self->{fb}} ? $#{$self->{fb}} : 0;
}

sub k_save {
	my $self = shift;
	my $file = $self->{parent}{cache}{last_file} || $self->find_available_file;
	my $string = join("\n", @{$self->{fb}})."\n";
	print locate(reverse(@{$self->{size}})), "\n";
	my $file = $self->read_question("File name? [$file] ") || $file;
	$file = $self->{parent}->abs_path($file);
	my $bit = 1;
	if ( -e $file ) {
		my $answer = $self->read_question("File exists - overwrite ? [yN] ") || "n";
		$self->{parent}->del_one_hist;
		unless ($answer =~ /y/i) { $bit = 0; }
	}
	if ($bit) {
		$bit = open FILE, ">$file";
		if ($bit) {
			print FILE $string;
			print "Wrote file $file\n";
		}
		else { print "Could not open file $file - do you have permissions ?\n"; }
		close FILE;
	}
	else { print "Did not write to file.\n"; }
	$self->{fb} = [];
}

sub find_available_file {
	my $self = shift;
	my $file = "";
	my $number = 1;
	while (!$file) {
		unless ( -e "untitled".hex($number) ) { $file = "untitled".hex($number); }
		else { $number++ }
	}
	return $file;
}

sub multi_line_switch { # keep track of multi line char table
	# TODO more flexible automated multiline
	my $self = shift;
	$self->{pos} = [length($self->{fb}[-1]), $#{$self->{fb}}]; # set cursor at end of buffer and print this cursor
	$self->print_buffer;
	if ($self->{multi_line_on}) {
		$self->{multi_line_on} = 0;
		$self->{char_table}{in_use} = $self->{char_table}{pre_multi};
	}
	else {
		$self->{multi_line_on} = 1;
		$self->{char_table}{pre_multi} = $self->{char_table}{in_use};
		$self->{char_table}{in_use} = $self->{parent}->pd_merge($self->{char_table}{in_use}, $self->{char_table}{multi});
		# merge uses dclone - hope it saves our ass
	}
}

sub probe {
	my $self = shift;
	ReadMode("raw");
	while ( my ($table, $keys) = each %{$self->{probe}} ) {
		$self->{char_table}{$table} = {};
		my @keys = @{$keys};
		my $title = shift @keys;
		print "For table \"$title\" please type the following characters:\n";
		print "\t Description\t -- Suggestion\n";
		foreach my $ref (@keys) {
			print "\t".$ref->[0]."\t -- ".$ref->[1]."\t  >> ";
			my @dus = ();
			while (not defined ($dus[0] = ReadKey(-1))) { }
			$dus[0] = ord($dus[0]);
			for (0..2) { push @dus, ord(ReadKey(-1)); } # non blocking
			for (0..2) { unless($dus[-1]) {pop @dus;} }
			my $key = join("-", @dus);
			$self->{char_table}{$table}{$key} = $ref->[2];
			print "made key $key\n";
		}
	}
	ReadMode("normal");
	if ($self->{config}{char_table_file}) {
		if ($self->{parent}->pd_write($self->{config}{char_table_file}, $self->{char_table})) { print "Wrote to file: ".$self->{config}{char_table_file}."\n"; }
		else { print "Failed to write to: ".print "Wrote to file: ".$self->{config}{char_table_file}."\n"; }
	}
	else { print "No char table file set - configuration will be lost when you log out\n"; }
}

sub help {
	my $self = shift;
	my $body = "\tDefault keybindings are:\n\n";
	my $multi = "\tDefault keybindings for multi line modus are\n\n";
	foreach my $key (sort(@{$self->{probe}})) {
		$body .= "\t   ".$key->[0]."\t".$key->[1]."\n";
		if ($key->[2]) {$multi .= "\t   ".$key->[0]."\t".$key->[2]."\n";}
	}
	return $body."\n\n".$multi."\n";
	# TODO more specific help texts
}

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Zoidberg::Buffer - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::Buffer;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Zoidberg::Buffer, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.


=head1 AUTHOR


Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.


=head1 SEE ALSO

L<perl>.

=cut

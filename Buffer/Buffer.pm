package Zoidberg::Buffer;

our $VERSION = '0.1';

use Data::Dumper;
use POSIX qw/floor ceil/;
use Term::ReadKey;
#use Term::ANSIColor;
use Term::ANSIScreen qw/:screen :cursor/;
use Zoidberg::StringParse;
use Zoidberg::StringParse::Syntax;
use strict;

use base 'Zoidberg::Fish';

$| = 1;

sub init {
	my $self = shift;
	#print "debug: buffer config: ".Dumper($self->{config})."\n";
	$self->{tab_string} = $self->{config}{tab_string} || "    ";
	$self->{parser} = Zoidberg::StringParse->new($self->parent->{grammar}, 'buffer_gram');
	$self->{syntax_parser} = Zoidberg::StringParse::Syntax->new($self->parent->{grammar}{syntax}, 'PERL', $self->parent->{grammar}{ansi_colors});

	# set default char table
	$self->{char_table}{in_use} = {
		4 => 	"k_ctrld",	# ^D -- left this default value for safety - to be able to exit :)
		10 =>	"k_newl",	# \n -- to be able to submit "b_probe"
	};

	# set probe values
	$self->{probe} = { # TODO pluggable maken
		'in_use' => [
			'Normal keybindings',
			["Magick char", "", "k_magick"],
			["Golf char", "Ctrl-g", "k_golf"],
			["Logout / quit", "Ctrl-d", "k_ctrld"],
			["Discard", "Ctrl-c", "k_ctrlc"],	# TODO ? $SIG{INT}
			["Suspend job", "Ctrl-z", "k_ctrlz"], # TODO : siggit!
			["Save to file", "Ctrl-o", "k_save"],
			["Read from file", "Ctrl-r", "k_open"],
			["Expand", "tab", "k_expand"],
			["Backspace", "Bcksp", "k_backspc"],
			["Fast Backspace", "Bcksp", "k_backspc('fast')"],
			["Submit", "Return", "k_newl"],
			["Multiline modus switch", "Insert", "multi_line_switch"],
			["Delete", "Del", "k_delete"],
			["Home", "Home", "k_home"],
			["End", "End", "k_end"],
			["History jump back", "Pg Up", "k_pgup"],
			["History jump forward", "Pg dw", "k_pgdw"],
			["Move left", "<- left", "k_moveleft"],
			["Move right", "-> right", "k_moveright"],
			["Fast left", "Ctrl <-", "k_moveleft('fast')"],
			["Fast right", "Ctrl ->", "k_moveright('fast')"],
			["History one back", "up", "k_hist_back"],
			["History one forward", "down", "k_hist_forw"],
		],
		'multi' => [
			'Keybindings for multiline modus',
			["Submit", "Ctrl-d", "k_m_ctrld"],
			["Tab", "tab", "k_tab"],
			["Expand", "Ctr-t", "k_expand"],
			["Newline", "Return", "k_m_newl"],
			["Move up", "up", "k_moveup"],
			["Move down", "down", "k_movedown"]
		]
	};
	if ($self->{config}{probe}) {$self->{probe} = $self->{config}{probe}; } # no merging here - would give rubish

	if ($self->{config}{char_table_file} && -s $self->{config}{char_table_file}) { $self->{char_table} = $self->{parent}->pd_read($self->{config}{char_table_file}); }
	elsif ($self->{config}{skel_char_table_file} && -s $self->{config}{skel_char_table_file}) { $self->{char_table} = $self->{parent}->pd_read($self->{config}{skel_char_table_file}); }
	else {
		$self->parent->print("No char table found - no file set, file empty or file does not exist ..\nTo probe chars enter \"Buffer->probe\".", 'warning');
	}
	#print "Debug: ".Dumper($self);
}

sub size { return (GetTerminalSize())[0,1]; } # width in characters, height in characters

sub read {
	my $self = shift;
	$self->{continu} = 1;
	$self->{size} = [$self->size];	# width in characters, height in characters
	#print "debug: size ".join(",", @{$self->{size}})."\n";
	my $fb = $self->{parent}->History->suggest;
	$self->{fb} = [$fb];
	$self->{pos} = [length($fb), 0]; 	# x,y cursor
	$self->{lines} = 0;
	$self->{last_quest} = $fb; # used to make the history more flex
	$self->{tab_exp_back} = [ ["", ""], [$fb, ""] ]; # used to flex up backspace [ [match_string, replace_string], ... ]
	$self->print_prompt;
	$self->print_buffer;
	while ($self->{continu}) {
		my $key;
		ReadMode("raw");
 		{
			local $SIG{WINCH} = sub {
				local $SIG{WINCH} = 'IGNORE';
				$self->{size} = [$self->size];
				$self->{lines} = 0;
				$self->print_prompt;
				$self->print_buffer;
			};
			while (not defined ($key = ReadKey(0.05))) { } # Timeout 1/20 sec - do people type faster then 20 chars/sec ?
		}
		if (ord($key) == 27) {	# escape char -- moet ook configureerbaar - -zou ook simpeler moeten - twee keer zelfde code is vunzig
			my @dus = (27);
			for (0..2) { push @dus, ord(ReadKey(0.01)); }
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
	my $fr = join("\n", @{$self->{fb}});
	$self->{parent}->History->add_history($fr, $self->{tab_exp_back});
	$self->{parent}->History->set_exec_last; # acknowledge execution
	return $fr;
}

sub read_question {
	my $self = shift;
	my $prompt = shift;
	if (ref($prompt)) {
		$self->{prompt} = $prompt->stringify;
		$self->{prompt_lenght} = $prompt->getLength + 1;
	}
	else {
		$self->{prompt} = $prompt;
		$self->{prompt_lenght} = length($prompt) + 1;
		$self->{custom_prompt} = 1;
	}
	my $answer = $self->read;
	$self->{custom_prompt} = 0;
	return $answer;
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
	my $lines = floor((length($self->{fb}[0]) + $self->{prompt_lenght})/ $self->{size}[0]); #/
	$space[0] = (($lines+1) * $self->{size}[0]) - (length($self->{fb}[0]) + $self->{prompt_lenght}) + 1;
	if ($#{$self->{fb}} > 0) {
		for (1 .. $#{$self->{fb}}) {
			my $i = $_;
			$start[$i] = ++$lines;
			my $my_lines = floor(length($self->{fb}[$i])/ $self->{size}[0]); #/
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
	my @buffer = $self->highlight;
	#print locate(0,0), "debug: lines $lines null_line $null_line   ";
	print locate($null_line , $self->{prompt_lenght}), $buffer[0].(" "x$space[0]); # print buffer and overwrite any garbage
	if ($#{$self->{fb}} > 0) {
		for (1 .. $#buffer) {
			my $i = $_;
			print locate( ($null_line + $start[$i]), 0 ),  $buffer[$i].(" "x$space[$i]);
		}
	}

	# print empty lines
	if ($empty_lines) { print locate( ($self->{size}[1] - $empty_lines + 1), 0), " "x($empty_lines * $self->{size}[0]); }

	#set cursor - be aware of line length
	my $c_off = 1;
	if ($self->{pos}[1] == 0) { $c_off = $self->{prompt_lenght}; }
	my $pos = $self->{pos}[0];
	if ($pos > length($self->{fb}[$self->{pos}[1]])) { $pos = length($self->{fb}[$self->{pos}[1]]); }
	my $c_line = floor(($pos + $c_off - 1)/ $self->{size}[0]); #/
	my $c_x = ($pos + $c_off) % ($self->{size}[0]);
	unless ($c_x) { $c_x = $self->{size}[0]; } # dit is luizige hack - nog s naar kijken
	#print locate (0, 0), "debug: c_line $c_line c_x $c_x pos+c_off ".($pos + $c_off)." size[0] ".($self->{size}[0]);
	print locate( ($null_line + $start[$self->{pos}[1]] + $c_line),  $c_x);
}

sub print_list {
	my $self = shift;
	my @strings = @_;
	my $longest = 0;
	map {if (length($_) > $longest) { $longest = length($_);} } @strings;
	unless ($longest) { return 0; }
	$longest += 2; # we want two spaces to saperate coloms
	my $cols = floor($self->{size}[0] / $longest);
	unless($cols > 1) { for (@strings) { print $_."\n"; } }
	else {
		my $rows = ceil(($#strings+1) / $cols);
		@strings = map {$_.(' 'x($longest - length($_)))} @strings;

		# <debug>
		#print "Debug: items: ".($#strings+1)." longest: $longest width: $self->{size}[0] => cols: $cols rows: $rows\n";
		#my $debug = "<".('-'x($longest-4)).">  ";
		#print $debug x $cols;
		#print "\n";
		# </debug>

		foreach my $i (0..$rows-1) {
			for (0..$cols) { print $strings[$_*$rows+$i]; }
			print "\n";
		}
	}
	return 1;
}

sub print_sql_list {
	my $self = shift;
	my @records = @_;
	my @longest = ();
	@records = map {[map {s/\'/\\\'/g; "'".$_."'"} @{$_}]} @records; # escape quotes + safety quotes
	foreach my $i (0..$#{$records[0]}) {
		map {if (length($_) > $longest[$i]) {$longest[$i] = length($_);} } map {$_->[$i]} @records;
	}
	#print "debug: records: ".Dumper(\@records)." longest: ".Dumper(\@longest);
	my $record_length = 0; # '[' + ']' - ', '
	for (@longest) { $record_length += $_ + 2; } # length (', ') = 2
	if ($record_length <= $self->{size}[0]) { # it fits ! => horizontal lay-out
		my $cols = floor($self->{size}[0] / ($record_length+2)); # we want two spaces to saperate coloms
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

sub highlight { # dit is een work around zolang buffer niet transparant is
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	my $tree = $self->{parser}->parse($fb, 'pipe_gram', 1, 1);
	#print 'DEBUG: '.join('__', map {join('--', @{$_})} @{$tree})."\n";
	my $string = '';
	foreach my $ref (@{$tree}) {
		if ($self->parent->{grammar}{syntax}{$ref->[2]}) {
			$string .= $self->{syntax_parser}->parse($ref->[0], $ref->[2]);
		}
		else { $string .= $ref->[0]; }
		$string .= $ref->[1];
	}
	return split(/\n/, $string);
}

sub k_magick {
	my $self = shift;
	$self->insert_char(chr(30)); # hex(1E) = 30
}

sub k_golf { # TODO  implemented this the right way :)
    my $self = shift;
    if ($self->{multi_line_on}) {
        print "\nGolf char not yet implemented for multiline mode\n";
    }
    else {
        my $str = $self->{fb}[0];
        $str =~ s/^\{//;
        $str =~ s/\}$//;
        my $l = length($str);
        print "\nLength: $l\n";
    }
    $self->print_prompt;
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
	elsif ($self->{pos}[0] > 0) { 
		$self->{pos}[0]--;
		if ($_[0] eq 'fast') {
			while ( (substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0]-1, 1) ne ' ') && ($self->{pos}[0] > 0)) {
				$self->{pos}[0]--;
			}
		}
	}
	elsif ($self->{pos}[1] > 0) {
		$self->{pos}[1]--;
		$self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]);
	}
}

sub k_moveright {
	my $self = shift;
	if ($self->{pos}[0] > length($self->{fb}[$self->{pos}[1]])) { $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]) }
	elsif ($self->{pos}[0] < length($self->{fb}[$self->{pos}[1]])) {
		$self->{pos}[0]++;
		if ($_[0] eq 'fast') {
			while ( (substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0], 1) ne ' ') && ($self->{pos}[0] < length($self->{fb}[$self->{pos}[1]]))) {
				$self->{pos}[0]++;
			}
		}
	}
	elsif ($self->{pos}[1] < $#{$self->{fb}}) {
		$self->{pos}[1]++;
		$self->{pos}[0] = 0;
	}
}

sub k_hist_back {
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	unless ($fb eq $self->{last_quest}) { $self->{parent}->History->add_history($fb, $self->{tab_exp_back}); }
	my @hist = $self->{parent}->History->get_hist("back");
	$self->{last_quest} = $hist[1];
	$self->{tab_exp_back} = $hist[3] || [["", ""]];
	@{$self->{fb}} = split(/\n/, $hist[1]);
	$self->{pos}[0] = length(@{$self->{fb}}[-1]);
	$self->{pos}[1] = @{$self->{fb}} ? $#{$self->{fb}} : 0;
}

sub k_hist_forw {
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	unless ($fb eq $self->{last_quest}) { $self->{parent}->History->add_history($fb, $self->{tab_exp_back}); }
	my @hist = $self->{parent}->History->get_hist("forw");
	$self->{last_quest} = $hist[1];
	$self->{tab_exp_back} = $hist[3] || [["", ""]];
	@{$self->{fb}} = split(/\n/, $hist[1]);
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
	$self->{fb} = [""];
	$self->{continu} = 0;
	$self->parent->exit;
	print "\n";
}

sub k_ctrlc {
	my $self = shift;
	if ($self->{multi_line_on}) { $self->multi_line_switch; }
	$self->{parent}->History->add_history( join("\n", @{$self->{fb}}), $self->{tab_exp_back});
	$self->{continu} = 0;
	$self->{fb} = [""];
	print "\n";
}

sub k_ctrlz {
    my $self = shift;
    print "ZZZZZZZZZZZZAp!!!!\n";
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

sub k_expand { # TODO rekening houden met cursor positie
	my $self = shift;
	my $regel = $self->{fb}[$self->{pos}[1]];

	my ($message, $fb, $ref) = $self->{parent}->Intel->expand(join("\n", @{$self->{fb}}));
	@{$self->{fb}} = split("\n", $fb);
	$self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]);

	unless ($regel eq $self->{fb}[$self->{pos}[1]]) { # create fancy backspace feature
		push @{$self->{tab_exp_back}}, [$self->{fb}[$self->{pos}[1]], $regel];
	}

	if (@{$ref}) {
		#print "debug: ".Dumper($ref);
		print "\n";
		if ($message) {
			$message =~ s/\n?$/\n/;
			print $message;
		}
		$self->print_list(@{$ref});
		$self->print_prompt;
	}
	elsif ($message) {
		$message =~ s/\n?$/\n/;
		print "\n".$message;
		$self->print_prompt;
	}

	$self->print_buffer;
}

sub k_backspc {
	my $self = shift;
	if (($self->{pos}[0] == 0) && ($self->{pos}[1] > 0)) {		# remove line break
		$self->k_moveleft;
		$self->{fb}[$self->{pos}[1]] .= $self->{fb}[$self->{pos}[1]+1];
		splice(@{$self->{fb}}, $self->{pos}[1]+1, 1);
	}
	elsif ($_[0] eq 'fast') {
		while ( (substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0]-1, 1) ne ' ') && ($self->{pos}[0] > 0)) {
			$self->k_moveleft;
		        $self->k_delete;
		}
		$self->k_moveleft;
                $self->k_delete;
	}
	elsif ($self->{pos}[0] > 0) {
		my $exp_length = length($self->{tab_exp_back}[-1][0]);
		#print "debug: ".Dumper($self->{tab_exp_back});
		if ($self->{tab_exp_back}[-1][0] && (substr($self->{fb}[$self->{pos}[1]], ($self->{pos}[0] - $exp_length), $exp_length) eq $self->{tab_exp_back}[-1][0])) {
			# is string in front of cursor matches last tab_exp - replace with old buffer
			for (1..$exp_length) {
				$self->k_moveleft;
				$self->k_delete;
			}
			my @chars = split(//, $self->{tab_exp_back}[-1][1]);
			foreach my $char (@chars) { $self->insert_char($char); } # dit moet mooier kunnen
			pop @{$self->{tab_exp_back}};
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
	unless ($fb eq $self->{last_quest}) { $self->{parent}->History->add_history($fb, $self->{tab_exp_back}); }
	my @hist = $self->{parent}->History->get_hist("back", 10);
	$self->{last_quest} = $hist[1];
	$self->{tab_exp_back} = $hist[3] || [["", ""]];
	@{$self->{fb}} = split(/\n/, $hist[1]);
	$self->{pos}[0] = length($self->{fb}[-1]);
	$self->{pos}[1] = @{$self->{fb}} ? $#{$self->{fb}} : 0;
}

sub k_pgdw {
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});
	unless ($fb eq $self->{last_quest}) { $self->{parent}->History->add_history($fb, $self->{tab_exp_back}); }
	my @hist = $self->{parent}->History->get_hist("forw", 10);
	$self->{last_quest} = $hist[1];
	$self->{tab_exp_back} = $hist[3] || [["", ""]];
	@{$self->{fb}} = split(/\n/, $hist[1]);
	$self->{pos}[0] = length($self->{fb}[-1]);
	$self->{pos}[1] = @{$self->{fb}} ? $#{$self->{fb}} : 0;
}

sub k_open {
	my $self = shift;
	my $file = $self->{parent}{cache}{last_file};
	print locate(reverse(@{$self->{size}})), "\n";
	$file = $self->read_question("File name? [$file] ") || $file;
	$self->{parent}->History->del_one_hist;
	$file = $self->{parent}->abs_path($file);
	if (-e $file) {
		$self->{parent}->History->add_history(join("\n", @{$self->{fb}}), $self->{tab_exp_back});
		if (open IN, $file) {
			@{$self->{fb}} = (<IN>);
			close IN;
			$self->{parent}{cache}{last_file} = $file;
			$self->{continu} = 1;
		}
		else { print "Could not open file $file.\n"; }
	}
	else { print "No such file $file\n"; }
}

sub k_save {
	my $self = shift;
	my $file = $self->{parent}{cache}{last_file} || $self->find_available_file;
	my $string = join("\n", @{$self->{fb}})."\n";
	print locate(reverse(@{$self->{size}})), "\n";
	$file = $self->read_question("File name? [$file] ") || $file;
	$self->{parent}->History->del_one_hist;
	$file = $self->{parent}->abs_path($file);
	my $bit = 1;
	if ( -e $file ) {
		my $answer = $self->read_question("File exists - overwrite ? [yN] ") || "n";
		$self->{parent}->History->del_one_hist;
		unless ($answer =~ /y/i) { $bit = 0; }
	}
	if ($bit) {
		if (open FILE, ">$file") {
			print FILE $string;
			print "Wrote file $file\n";
			close FILE;
			$self->{parent}{cache}{last_file} = $file;
		}
		else { print "Could not open file $file - do you have permissions ?\n"; }
	}
	else { print "Did not write to file.\n"; }
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
	while ( my ($table, $keys) = each %{$self->{probe}} ) {
		$self->{char_table}{$table} = {};
		my @keys = @{$keys};
		my $title = shift @keys;
		print "For table \"$title\" please type the following characters:\n";
		print "\t Description\t -- Suggestion\n";
		foreach my $ref (@keys) {
			print "\t".$ref->[0]."\t -- ".$ref->[1]."\t  >> ";
			my @dus = ();
			ReadMode("raw");
			while (not defined ($dus[0] = ReadKey(0.05))) { }
			$dus[0] = ord($dus[0]);
			for (0..2) { push @dus, ord(ReadKey(0.01)); }
			ReadMode("normal");
			for (0..2) { unless($dus[-1]) {pop @dus;} }
			my $key = join("-", @dus);
			$self->{char_table}{$table}{$key} = $ref->[2];
			print "made key $key\n";
		}
	}
	if ($self->{config}{char_table_file}) {
		if ($self->{parent}->pd_write($self->{config}{char_table_file}, $self->{char_table})) { 
			print "Wrote to file: ".$self->{config}{char_table_file}."\n"; 
		}
		else { print "Failed to write to: ".$self->{config}{char_table_file}."\n"; }
	}
	else { print "No char table file set - configuration will be lost when you log out\n"; }
}

sub help {
	my $self = shift;
    my$body;
    map { $body.=(ref($_))?"\t$_->[0]\t$_->[1]\t$_->[2]\n":"$_\n\n" } @{$self->{probe}{in_use}};
    map { $body.=(ref($_))?"\t$_->[0]\t$_->[1]\t$_->[2]\n":"\n$_\n\n" } @{$self->{probe}{multi}};
	return "$body\n"
	# TODO more specific help texts
}

sub monkey { # TODO, obfuscate, hide, easter egg
	my $self = shift;
	my ($i, $key, $number) = (0, -1, 0);
	my @list = ( " 0 \n---\n | \n/ \\", "|0|\n - \n | \n| |" );
	@list = map {join("\n", map {'<     '.$_} split/\n/, $_)} @list;
	print "    What if .... AOL toke over FSF ?\n".("\n"x7);
	print locate($self->{size}[1]-4, 25), "You have to guess the number right.";
	local $SIG{WINCH} = sub { $self->{size} = [(GetTerminalSize())[0,1]]; };
	while (!$key || (($key != $number) && ($key ne 'g'))) {
		$i = $i ? 0 : 1;
		print locate($self->{size}[1]-6, 0), ('^'x$self->{size}[0])."\n".$list[$i]."\n".('^'x$self->{size}[0]);
		print locate($self->{size}[1]-5, $self->{size}[0]-1), ' ';
		ReadMode("raw");
		$key = ReadKey(0.05);
		ReadMode("normal");
		print locate($self->{size}[1]-5, 20), "YOU HAVE TO PLAY THE MONKEY TO GET YOUR SHELL BACK";
		if ($key) {
			$number = int(rand(10));
			print locate($self->{size}[1]-4, 25), "The number was $number ,                 ";
			print locate($self->{size}[1]-3, 30), "you guessed $key.  ";
		}
		for (2..5) { print locate($self->{size}[1]-$_, $self->{size}[0]), ">"; }
		sleep 1;
	}
	print locate($self->{size}[1]-3, 25), "The number was $number , you WIN !";
	print locate($self->{size}[1], $self->{size}[0]), "\n";
}

1;
__END__

=head1 NAME

Zoidberg::Buffer - The zoidberg input buffer

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This module generates a more dynamic input
buffer for the Zoidberg shell. It is a
core object for Zoidberg.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 read()

  Get input from prompt

=head2 read_question($question)

  Get input from custom prompt

=head2 k_*

  Methods to bind keys to

=head2 probe()

  Interactive probe key bindings

=head2 help()

  Output keybindings

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net

=cut

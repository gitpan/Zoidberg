package Zoidberg::Fish::Buffer;

our $VERSION = '0.42';

use strict;
use Data::Dumper;
use POSIX qw/floor ceil/;
use Storable qw/dclone/;
use Term::ReadKey;
use Term::ANSIScreen qw/:screen :cursor color/;
#use Zoidberg::StringParser;
# use Zoidberg::StringParser::Syntax;
use Zoidberg::Utils qw/:error :output debug read_data_file unique_file/;
use Zoidberg::DispatchTable;
#use Zoidberg::FormatedString;

use base 'Zoidberg::Fish';

$| = 1;

sub init {
	my $self = shift;
	$self->{tab_string} = $self->{config}{tab_string} || "    ";
#	$self->{parser} = Zoidberg::StringParser->new($self->parent->{grammar}, 'buffer_gram');
#	$self->{syntax_parser} = Zoidberg::StringParser::Syntax->new($self->parent->{grammar}{syntax}, 'PERL', $self->parent->{grammar}{ansi_colors});

	$self->{char_table} = read_data_file('char-table');

	my %bindings;
	tie %bindings, 'Zoidberg::DispatchTable', $self, read_data_file('key-bindings');
	$self->{bindings} = \%bindings;

	$self->{fb} = ['']; # important -- define fb

	$self->switch_modus;

#	$self->{ps1} =	$ENV{PS1}
#			? Zoidberg::FormatedString->new(\$ENV{PS1})
#			: ($> == 0) ? '#' : '$' ;

	$self->{state} = 'idle';
}

#######################
## Extrnal interface ##
#######################

sub size { return (GetTerminalSize())[0,1]; } # width in characters, height in characters

sub erase_buffer { print locate($_[0]->{_null_line}, 0), "\e[J" } # untested

sub get_string {
	my $self = shift;

	# set prompt
	if ($_[0]) {
		my $prompt = shift;
		$self->{custom_prompt} = 1;
		if (ref($prompt)) {
			$self->{prompt} = $prompt->stringify;
			$self->{prompt_lenght} = $prompt->getLength;
		}
		else {
			$self->{prompt} = $prompt;
			$self->{prompt_lenght} = length($prompt);
		}
	}

	# set internal state
	$self->{continu} = 1;
	$self->{size} = [$self->size];	 			# width in characters, height in characters
	$self->{pos} = [length($self->{fb}[-1]), 0]; 		# x,y cursor
	$self->{_last_quest} = dclone($self->{fb});		# used to make the history more flex
	$self->{tab_exp_back} = [ [join("\n", @{$self->{fb}}), ""] ];	# used to flex up backspace [ [match_string, replace_string], ... ]

	# listen for keys
	while ($self->{continu}) {
		$self->refresh;
		$self->_do_key($self->_read_key);
	}

	# put in history
	$self->history_add;
	$self->{parent}->History->set_prop('e', 1); # acknowledge execution, e for exec

	# reset internal state for next call
	my $fb = join("\n", @{$self->{fb}})."\n";
	$self->{custom_prompt} = 0;
	$self->reset;
	print "\n";

	return $fb;
}

sub ask { # FIXME should be implemented at another level
	my ($self, $quest, $default, $prompt) = @_;
	unless ($prompt) {
		$prompt = $quest;
		$prompt .=
			('Y' eq uc $default) ? ' [Yn] ' :
			('N' eq uc $default) ? ' [yN] ' :
			$default ? " [$default] " : ''  ;
	}
	my $string = $self->get_string($prompt);
	chomp $string;
	$string ||= $default;
	if ($default =~ /^y|n$/i) {
		return 1 if $string =~ /^y|yes$/i;
		return 0 if $string =~ /^n|no$/i;
		return $self->ask($quest, $default, $prompt); # recurs; try again
	}
	return $self->ask($quest, $default, $prompt)
		unless length $string; # recurs; try again
	return $string;
}

sub insert_string {
	my ($self, $string) = (@_);
	$self->{pos}[0] = length($self->{fb}[$self->{pos}[1]])
		if $self->{pos}[0] > length $self->{fb}[$self->{pos}[1]];
	my @dus = split("\n", $string);
	my $start = substr($self->{fb}[$self->{pos}[1]], 0, $self->{pos}[0], "");
	my $end = $self->{fb}[$self->{pos}[1]];
	$dus[0] = $start.$dus[0];
	$self->{pos}[0] = length($dus[-1]);
	$self->{pos}[1] += $#dus; # null based
	$dus[-1] .= $end;
	splice(@{$self->{fb}}, $self->{pos}[1], 1, @dus);
}

sub set_string {
	my $self = shift;
	@{$self->{fb}} = map {$_."\n"} map {split(/\n/, $_)} @_;
}

sub rub_out {
	my $self = shift;
	my $len = shift || 1;
	if ($self->{pos}[0] > length($self->{fb}[$self->{pos}[1]])) { $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]) }
	if ($len < 0) {
		$len *= -1;
		$self->{pos}[0] -= $len;
	}
	substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0], $len, "");

}

sub bell { $_[0]->{config}{bell}->(@_) }

sub respawn {
	my $self = shift;
	$self->{_r_lines} = 0;
	$self->refresh;
}

sub reset {
	my $self = shift;
	$self->{pos} = [0, 0];
	$self->{_r_lines} = 0;
	$self->{_last_quest} = [];
	$self->{tab_exp_back} = [ ["", ""] ];
	$self->{fb} = [''];
	$self->{state} = 'idle';
	$self->switch_modus($self->{config}{default_modus});
}

sub refresh {
	my $self = shift;
	unless ($self->{custom_prompt}) {
		$self->{prompt} = $self->{parent}->Prompt->stringify;
		$self->{prompt_lenght} = $self->{parent}->Prompt->getLength;
	}

	# TODO a sub 'translate' to get the rigth lenghts (no escapes and non \w shit etc)
	my @lengths = map {length($_)} @{$self->{fb}};

	my @lines = $self->highlight;
	my @off = ();
	$lines[0] = $self->{prompt}.$lines[0];
	$off[0] = $self->{prompt_lenght};

	# line numbers
	if ($self->{options}{nu} && ($#{$self->{fb}} > 0)) {
		my $pad = length($#lines);
		for (1..$#{$self->{fb}}) {
			my $n = $_.(" "x($pad - length($_)));
			$lines[$_] = $n." : ".$lines[$_];
			$off[$_] += $pad + 3;
		}
	}

	# calculate lines
	for (0..$#off) { $lengths[$_] += $off[$_]; }
	my $r_lines = floor($lengths[0]/$self->{size}[0]);
	my @start = (0);
	foreach my $i (1 .. $#lengths) {
		$start[$i] = ++$r_lines; # +1
		$r_lines += floor($lengths[$i]/$self->{size}[0]); #/
	}

	# move previous lines up
	my $e_lines = 0;
	if ($r_lines < $self->{_r_lines}) {
		$e_lines = $self->{_r_lines} - $r_lines;
		$r_lines = $self->{_r_lines};
	}
	else {
		print locate(reverse(@{$self->{size}})), "\n"x($r_lines - $self->{_r_lines});
		$self->{_r_lines} = $r_lines;
	}

	# print lines
	$self->{_null_line} = $self->{size}[1] - $r_lines;
	#print locate(), "debug: ".join('-', @start)." -- ".join('-', @lines);
	foreach my $i (0 .. $#lengths) { print locate($self->{_null_line} + $start[$i], 0), $lines[$i], "\e[K"; }

	# print empty lines
	if ($r_lines) { print "\e[J"; }

	# do some hack
	$self->print_info;

	# set cursor
	my $x_pos = $self->{pos}[0];
	$x_pos += $off[$self->{pos}[1]];
	if ($x_pos > $lengths[$self->{pos}[1]]) { $x_pos = $lengths[$self->{pos}[1]]; }
	my $y_pos = floor($x_pos / $self->{size}[0]);
	$x_pos -= $y_pos * $self->{size}[0];
	$x_pos += 1;
	print locate($self->{_null_line} + $start[$self->{pos}[1]] + $y_pos, $x_pos);
    $self->broadcast('buffer_refresh');
}

#######################
## private interface ##
#######################

sub _read_key { # TODO clean up
	my $self = shift;
	my $chr;
	ReadMode("raw");
	{
		local $SIG{WINCH} = sub {
			local $SIG{WINCH} = 'IGNORE';
			$self->{size} = [$self->size];
			$self->{lines} = 0;
			$self->refresh;
		};
		while (not defined ($chr = ReadKey(0.05))) { $self->broadcast($self->{state}) }

		#<VUNZIG> this will cause bugs
		if ($chr eq "\e") {
			my $str = ReadKey(0.01);
			if ($str) {
				my @poss = grep /^\Q$str\E/, keys %{$self->{char_table}{esc}};
				while (@poss) {
					my $my_chr;
					while ( not defined ($my_chr = ReadKey(0.05)) ) {
						$self->broadcast($self->{state})
					}
					$str .= $my_chr;
					@poss = grep /^\Q$str\E/, keys %{$self->{char_table}{esc}};
					last if @poss == 1 and $poss[0] eq $str;
				}
				if (@poss == 1) { $chr = $poss[0] }
				else {
					$self->_do_key('esc');
					$chr = $str;
				}
			} # else just char = \e
		}
		#</VUNZIG>

	}
	ReadMode("normal");

	$self->{state} = 'typing';

	unless (length($chr) > 1) {
		my $ord = ord($chr);
		if ($self->{char_table}{$ord}) { $chr = $self->{char_table}{$ord}}
		elsif ($ord == 0) { $chr = 'ctrl_@'; }
		elsif ($ord < 27) { $chr = 'ctrl_'.(chr $ord + 96); }
		elsif ($ord < 32) { $chr = 'ctrl_'.(chr $ord + 64); }
		elsif ($ord == 127) { $chr = 'delete'; }
	}
	elsif ($self->{char_table}{esc}{$chr}) {$chr = $self->{char_table}{esc}{$chr} }
    
	return $chr;
}

sub _test_key {
	my $self = shift;
	my @dus = ();
	ReadMode("raw");
	print 'press any key or key combination';
	while (not defined ($dus[0] = ReadKey(0.05))) { }
	$dus[0] = ord($dus[0]);
	for (0..10) { push @dus, ord(ReadKey(0.01)); }
	ReadMode("normal");
	for (0..10) { unless($dus[-1]) {pop @dus;} }
	print "got key: -".join("-", @dus)."- char: -".join("-", map {($_ eq ord("\e")) ? 'ESC' : chr($_)} @dus)."-\n";
}

sub _do_key {
	my $self = shift;
	my $chr = shift;

	if (exists $self->{bindings}{$self->{current_modus}}{$chr}) {
		$self->{bindings}{$self->{current_modus}}{$chr}->(@_);
	}
	elsif (exists $self->{bindings}{_all}{$chr}) { 
		$self->{bindings}{_all}{$chr}->(@_);
	}
	elsif ($self->can('k_'.$chr)) {
		my $sub = 'k_'.$chr;
		$self->$sub(@_);
	}
	else { $self->default($chr, @_) }
}

##############################
## Binding related routines ##
#############################

sub switch_modus {
	my $self = shift;
	my $modus = shift || $self->{config}{default_modus};
	if (my $class = $self->{config}{modi}{$modus}) {
		eval "require $class";
		error "Failed to load class: $class ($@)" if $@;
		debug "entering '$modus' buffer mode using class $class";
		$self->_switch_off(@_);
		bless $self, $class;
		$self->{current_modus} = $modus;
		$self->_switch_on(@_);
	}
	else { error "No class defined for buffer modus \"$modus\"" }
}

# overloadable hooks
sub _switch_on {}
sub _switch_off {}

sub probe {
	my $self = shift;
	if (my $name = shift) {
		print "Please type (Ctrl_c to skip)   \"$name\"\t>";
		my $chr;
		ReadMode("raw");
		while (not defined ($chr = ReadKey(0.05))) {} # do nothing
		if ($chr eq "\e") { # VUNZIG this will cause bugs
			my @dus;
			for (0..5) { push @dus, ReadKey(0.01); }
			ReadMode("normal");
			my $str = join('', @dus);
			if ($str) {
				print " ESC $str\n";
				$self->{char_table}{esc}{$str} = $name;
				return;
			}
		}
		elsif ((ord($chr) == 3) && ($name ne 'ctrl_c')) { print " skipped\n" ; }
		else {
			print " ".ord($chr)."\n";
			$self->{char_table}{ord($chr)} = $name;
		}
		ReadMode("normal");
	}
	else { # probe all by recursion
		my @keys = sort map {ref($_)?values(%{$_}):$_} values %{$self->{char_table}};
		my @dus;
		foreach my $k (@keys) { unless (grep {$_ eq $k} @dus) { push @dus, $k; } }
		for (@dus) { $self->probe($_); } 
	}
}

sub bind {
	my $self = shift;
	my $e = 'Usage: bind($char_name, $sub_name, $modus) -- $modus is optional';
	my $chr = shift || complain $e, 'error';
	my $sub = shift || complain $e, 'error';
	my $modus = shift || $self->{config}{default_modus};
	$self->{bindings}{$modus}{$chr} = $sub;
}

sub help {
	my $self = shift;
	# TODO
}

#############################
## Some basic key bindings ##
#############################

sub k_ctrl_d {
	my $self = shift;
	if ($self->{settings}{ignoreeof}) { message 'Setting \'ignoreeof\' in effect.' }
	elsif (join '', @{$self->{fb}}) { $self->bell } # make accidental ^d less harmfull
	else {
		$self->reset;
		$self->{continu} = 0;
		$self->parent->exit;
		# FIXME last line should be enough
	}
}

sub k_ctrl_c { $_[0]->discard }

sub k_ctrl_z {}

sub k_up { $_[0]->history_get('prev'); }

sub k_down { $_[0]->history_get('next'); }

sub k_magick { $_[0]->default("\xA3"); }

###################################
## Routines used by key bindings ##
###################################

sub default { $_[0]->insert_string($_[1]); }

sub clear {
	print cls;
	$_[0]->respawn;
}

sub discard {
	my $self = shift;
	$self->history_add;
	$self->reset;
	print "\n";
	$self->respawn;
}

sub submit { $_[0]->{continu} = 0 }

sub history_add { 

if (join('', @{$_[0]->{fb}})) { $_[0]->{parent}->History->add($_[0]->{fb}, $_[0]->{tab_exp_back}); } }

sub history_get {
	my $self = shift;

	unless (_arr_eq($self->{fb}, $self->{_last_quest})) { $self->history_add; }

	my ($fb, $arg, $prop) = $self->{parent}->History->get(@_);

	$self->{_last_quest} = dclone($fb);
	$self->{tab_exp_back} = shift @{$arg} || [["", ""]];

	$self->{fb} = $fb;
	$self->{pos} = @{$self->{fb}} ? [length(@{$self->{fb}}[-1]), $#{$self->{fb}}] : [0, 0] ;
}

sub _arr_eq {
	my $ref1 = pop;
	my $ref2 = pop;
	unless ($#{$ref1} == $#{$ref2}) { return 0; }
	foreach my $i (0..$#{$ref1}) { unless ($ref1->[$i] eq $ref2->[$i]) { return 0; } }
	return 1;
}

=begin comment

sub golf {
	my $self = shift;
	my $fb = join ("\n", @{$self->{fb}});
	print	"\n",
		color('blue'), "--[", color('reset'),
		" Total length: ",
		color('yellow'), length($fb), color('reset'),
		" chr. ",
		color('blue'), "]", color('reset')
	;
	if (my ($ref) = reverse grep {$_->[2] eq 'PERL'} @{$self->{parser}->parse($fb, 'pipe_gram', 1, 1)}) {
		$ref->[0] =~ s/(^\s*\w*{|}(\w*)\s*$)//g;
		print	color('blue'), "--[", color('reset'),
			" Last perl block: ",
			color('yellow'), length($ref->[0].$2), color('reset'),
			" chr. ",
			color('blue'), "]", color('reset')
		;
	}
	print "\n";
	$self->respawn;
}

=end comment

=cut

sub editor {
	my $self = shift;
	my $ext = 'pl'; # TODO make this dynamic
	my $editor = $self->parent->{settings}{utils}{editor} || $ENV{EDITOR} || 'vi';
	my $tempfile = unique_file("/tmp/zoid-fc-XXXX.".$ext);
	debug "editor used: $editor, tempfile: $tempfile";
	open(TEMP,'>'.$tempfile);
	print TEMP join("\n", @{$self->{fb}});
	close TEMP;
	system($editor, $tempfile);
	open(TEMP,$tempfile);
	@{$self->{fb}} = map {chomp $_; $_} (<TEMP>);
	@{$self->{fb}} = ('') unless @{$self->{fb}};
	close TEMP;
	unlink($tempfile);
	$self->{pos} = [length($self->{fb}[-1]), $#{$self->{fb}}];
	$self->refresh;
	$self->submit;
}

sub move_left {
	my $self = shift;
    my ($cnt,$opt);
    for (@_) {
        /^\d+$/&& ($cnt=$_);
        /fast/i&& ($opt=$_);
    }
    unless ($cnt) { $cnt = 1 }
    for (1..$cnt) {
	    if ($self->{pos}[0] > length($self->{fb}[$self->{pos}[1]])) { $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]) }
	    elsif ($self->{pos}[0] > 0) {
		    $self->{pos}[0]--;
		    if ($opt eq 'fast') {
			    while ( (substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0]-1, 1) ne ' ') && ($self->{pos}[0] > 0)) {
				    $self->{pos}[0]--;
			    }
		    }
	    }
	    elsif ($self->{pos}[1] > 0) { # $self->{pos}[0] = 0
		    $self->{pos}[1]--;
		    $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]);
	    }
	    else { $self->bell; last }
    }
}

sub move_right {
	my $self = shift;
    my ($cnt,$opt);
    for (@_) {
        /^\d+$/&& ($cnt=$_);
        /fast/i&& ($opt=$_);
    }
    unless ($cnt) { $cnt = 1 }
    for (1..$cnt) {
	    if ($self->{pos}[0] > length($self->{fb}[$self->{pos}[1]])) { $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]) }
    	elsif ($self->{pos}[0] < length($self->{fb}[$self->{pos}[1]])) {
    		$self->{pos}[0]++;
    		if ($opt eq 'fast') { 
    			while ( (substr($self->{fb}[$self->{pos}[1]], $self->{pos}[0], 1) ne ' ') && ($self->{pos}[0] < length($self->{fb}[$self->{pos}[1]]))) {
    				$self->{pos}[0]++;
    			}
    		}
    	}
    	elsif ($self->{pos}[1] < $#{$self->{fb}}) {  # $self->{pos}[0] = length($self->{fb}[$self->{pos}[1]])
    		$self->{pos}[1]++;
    		$self->{pos}[0] = 0;
    	}
    	else { $self->bell; last }
    }
}

sub move_up {
	my $self = shift;
    my $cnt = shift || 1;
    for (1..$cnt) {
	    if ($self->{pos}[1] > 0) { $self->{pos}[1]--; }
	    else { $self->bell; last }
    }
}

sub move_down {
	my $self = shift;
    my $cnt = shift || 1;
    for (1..$cnt) {
	    if ($self->{pos}[1] < $#{$self->{fb}}) { $self->{pos}[1]++; }
	    else { $self->bell; last }
    }
}


sub move_home { $_[0]->{pos}[0] = 0; }

sub move_end { $_[0]->{pos}[0] = length($_[0]->{fb}[$_[0]->{pos}[1]]); }

sub go_line {
    my $self = shift;
    my $line = shift || $#{$self->{fb}};
    $self->{pos}[1] = $line;
}

sub expand { # TODO fix tab_exp_back for expansion in het midden van de string
	my $self = shift;
	my $lucky_bit = shift;
	my $context = shift;
	my $regel = $self->{fb}[$self->{pos}[1]];

	my @end = (substr($self->{fb}[-1], $self->{pos}[0], (length($self->{fb}[-1])-$self->{pos}[0]), ''));
	if ($#{$self->{fb}} > $self->{pos}[1]) { push @end, splice (@{$self->{fb}}, $self->{pos}+1); }

	my ($message, $fb, $ref) = $self->{parent}->Intel->expand(
		join("\n", @{$self->{fb}}), $lucky_bit, $context);

	@{$self->{fb}} = split("\n", $fb);
	$self->{pos}[0] = length($self->{fb}[$self->{pos}[1]]);
	$self->{fb}[$self->{pos}[1]] .= shift @end;
	push @{$self->{fb}}, @end;

	unless ($regel eq $self->{fb}[$self->{pos}[1]]) { # create fancy backspace feature
		push @{$self->{tab_exp_back}}, [$self->{fb}[$self->{pos}[1]], $regel];
	}
	elsif (!@{$ref}) { $self->bell; } # no poss and no match

	return unless scalar(@{$ref}) || $message;
	print length($message) ? "\n".$message."\n" : "\n";

	if (scalar(@{$ref})) {
		#print "debug: ".Dumper($ref);
		if ( $$self{config}{max_expand} && @$ref > $$self{config}{max_expand}) {
			print "Display all ".scalar(@$ref).' possibilities? [yN] ';
			output $ref if <STDIN> =~ /y/i ;
		}
		else { output $ref }
	}

	$self->respawn;
}

sub open_file {}

sub save_file {}

#####################
## Hacks & garbage ##
#####################

sub highlight { # this belongs in a string util module or something
	my $self = shift;
	my $fb = join("\n", @{$self->{fb}});

	# do syntax highlighting

=cut

	my $tree = $self->{parser}->parse($fb, 'pipe_gram', 1, 1);
	my $error = $self->{parser}->{error};
	my $string = '';
	foreach my $ref (@{$tree}) {
		if ($self->parent->{grammar}{syntax}{$ref->[2]}) {
			$string .= $self->{syntax_parser}->parse($ref->[0], $ref->[2]);
		}
		else { $string .= $ref->[0]; }
		$string .= $ref->[1];
		$self->{_last_context} = $ref->[2];
	}

=cut

	my $string = $fb; my $error;

	# display hack
	if ($self->{config}{magick_char}) { $string =~ s/\xA3/$self->{config}{magick_char}/g; }
	
	#filthy hack -- TODO implement this kind of thing in the parser
	if (($error =~ /^Open block/) && ($self->{current_modus} eq 'insert')) {
		$self->{____auto_switch} = 1;
		$self->switch_modus('multi_line');
	}
	elsif ( !$error && ($self->{current_modus} eq 'multi_line') && $self->{____auto_switch}) {
		$self->{____auto_switch} = 0;
		$self->switch_modus('insert');
	}

	return split(/\n/, $string);
}

sub print_info {
	my $self = shift;

	## info bar
	if ($self->{config}{info}) {
		my @r = (
			"[ Context: ]--[ ".uc($self->{_last_context})." ]--",
			"[ Modus  : ]--[ ".uc($self->{current_modus})." ]--",
		);
		if (ref($self->{_saved_buff}) && @{$self->{_saved_buff}}) {
			my $int = $#{$self->{_saved_buff}} + 1;
			push @r, "[ Buffers: ]--[ $int ]--";
		}
		my $l = 0;
		for (@r) { if (length($_)>$l) { $l=length($_) }};
		@r = map { $_.("-"x($l - length $_)) } @r;
		for (0..$#r) {
			print	locate($_ + 1, $self->{size}[0] - $l),
				color('black', 'on_white'), $r[$_],
				color('reset');
		}
	}

	## xterm title
	## Sequences from the "How to change the title of an xterm" howto
	##  <http://sunsite.unc.edu/LDP/HOWTO/mini/Xterm-Title.html>
	if ($self->{config}{title} && $ENV{TERM}) {
		if ($ENV{TERM} =~ /^((ai)?xterm.*|dtterm)$/) {
			print "\033]0;$self->{config}{title}\007"
		}
		elsif ($ENV{TERM} eq 'iris-ansi') { print "\033P1.y$self->{config}{title}\033\\" }
		elsif ($ENV{TERM} eq 'sun-cmd') { print "\033]l$self->{config}{title}\033\\" }
		# TODO hpterm -- needs length -- wait for string format implementation
	}
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
		$self->bell;
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

__DATA__
$default = {
	char_table => {
		8 => "backspace",
		9 => "tab",
		10 => "return",
		27 => "esc",
		31 => "magick", # works for me
		127 => "backspace",
		'esc' => {
			'[A' => 'up',
			'[B' => 'down',
			'[C' => 'right',
			'[D' => 'left',
			'[F' => 'end',
			'[H' => 'home',
			'[1~' => 'home',
			'[2~' => 'insert',
			'[4~' => 'end',
			'[3~' => 'delete',
			'[5~' => 'page_up',
			'[6~' => 'page_down',
		},
	},
	bindings => {
		'meta' => {
			'i' => 'switch_modus(\'insert\')',
			'insert' => 'switch_modus(\'insert\')',
			'm' => 'switch_modus(\'multi_line\')',
			'o' => 'save_file',
			'r' => 'open_file',
			'q' => 'switch_info',
			'v' => 'editor',
			'g' => 'golf',
			'n' => 'new_buffer',
			'b' => 'rotate_buffer',
		},
		'insert' => {
			'page_up' => 'history_get(\'prev\', 10)',
			'page_down' => 'history_get(\'next\', 10)',
			'up' => 'history_get(\'prev\')',
			'down' => 'history_get(\'next\')',
		},
	},
}

__END__

=head1 NAME

Zoidberg::Fish::Buffer - The zoidberg input buffer

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This module provides a dynamic input
buffer for the Zoidberg shell.

=head2 EXPORT

None by default.

=head1 METHODS

FIXME

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>
R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Fish>,
L<http://zoidberg.sourceforge.net>

=cut

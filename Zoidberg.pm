package Zoidberg;

our $VERSION = '0.1';
our $VERSION_NAME = '-devel-unstable';
our $LONG_VERSION =
"Zoidberg - a modular perl shell, version $VERSION$VERSION_NAME
Copyright (c) 2002 Jaap G Karssenberg and R.L. Zwart";
our $DEVEL = 1;

use strict;
use vars qw/$AUTOLOAD/;
use utf8;
use Term::ANSIColor;
use Data::Dumper;
use Zoidberg::PdParse;
use POSIX;

push @Zoidberg::ISA, ("Zoidberg::PdParse");

sub new {
	my $class = shift;
	my $self = {};

	$self->{core}  = {};		# global configuration
	$self->{grammar} = {};		# parsing configuration
	$self->{cache}	= {};		# cache - TODO non caching option (?)
	$self->{events} = {};		# hash used for broadcasting events
	$self->{objects} = {};		# plugins as blessed objects
	$self->{vars} = {};		# persistent vars
	$self->{config} = {};		# plugin configuration

	$self->{core} = {
		'silent' => { 'output' => 0, 'warning' => 0, 'error' => 0, 'message' => 0, 'debug' => 1, },
		'core_objects' => [qw/Buffer Intel Prompt Commands History MOTZ/], # these have stub versions
		'clothes' => { 'keys' => [qw/core grammar config/], 'subs' => [qw//], }
	};
	$self->{round_up} = 1;
	$self->{exec_error} = 0;

	bless($self, $class);
}

sub init {
	my $self = shift;

	# print welcome message
	$self->print("## Welcome to the Zoidberg shell Version $VERSION$VERSION_NAME ##  ", 'message');

	# process fluff input
	$self->{fluff_input} = shift;
	for ( (grep {/_dir$/} keys %{$self->{fluff_input}}) , 'prefix') { $self->{fluff_input}{$_} =~ s/\/?$/\//; }

	foreach my $name (grep {/_file$/} keys %{$self->{fluff_input}}) {
		my $file = $self->{fluff_input}{$name};
		unless ($_ =~ /^\//) { $file = $self->{fluff_input}{config_dir}.$file; }
		$name =~ s/_file$//;
		my $pre_eval = 'my $prefix = \''.$self->{fluff_input}{prefix}.'\'; my $conf_dir = \''.$self->{fluff_input}{config_dir}.'\';';
		$self->{$name} = $self->pd_merge($self->{$name}, $self->pd_read($file, $pre_eval) );
	}

	# init various objects:
	while (my ($zoidname, $data) = each %{$self->{core}{init_objects}}) {
		my @args = ();
		if ($data->[1]) { @args = (ref($data->[1]) eq 'ARRAY') ? @{$data->[1]} : ($data->[1]); }
        	$self->init_postponed($zoidname, $data->[0], @args);
		if ($data->[2]) { eval($data->[2]); }
	}

	# init self
	$self->cache_path('init');
	$self->{StringParser} = Zoidberg::StringParse->new($self->{grammar}, 'script_gram');
	$self->MOTZ->fortune;
	$self->print("## Try typing \"->Buffer->probe\" if keybindings fail", 'message');
	$self->print("## Type help to get on your feet", 'message');
	if ($DEVEL) { $self->print("This is a developement version -- consider it unstable.", 'warning'); }
}

########################
#### main parsing routines ####
########################

sub main_loop {
	my $self = shift;
	$self->{core}{continu} = 1;
	$self->{rounded_up} = 0;
	while ($self->{core}{continu}) {
		$self->broadcast_event('precmd');
		if ($self->{objects}{Trog}) { $self->{no_trog_warnig} = 0; }
		elsif (!$self->{no_trog_warnig}) {
			$self->print("No Exec module \'Trog\' found -- only use very stripped down syntax.", 'warning');
			$self->{no_trog_warnig} = 1;
		}

		$self->cache_path; # moet dit ding hieruit en naar een event ???

		my $cmd = $self->Buffer->read;
		chomp $cmd; # just to be sure
		#print "Debug: cmd: $cmd\n";
		unless ($cmd =~ /^[\s\n]*$/) { $self->parse($cmd); } # speed hack

		$self->broadcast_event('postcmd');
		$self->wipe_cache; # moet dit ding hieruit en naar een event ???
	}
}

sub parse { # use: logic_or logic_and end_of_statement
	my $self = shift;
	$self->{exec_error} = 0;
	my @pending = map { @{$self->{StringParser}->parse($_, 'script_gram')} } grep $_, @_;
	if ($self->{StringParser}->{error}) {
		$self->print($self->{StringParser}->{error}, 'error');
		return "";
	}
	my ($re, $prev_sign) = ('', '');
	for (@pending) {
		my ($string, $sign) = @{$_};
		if ( $self->{exec_error} ?
			(grep {$prev_sign =~ /^$_$/} @{$self->{grammar}{logic_and}}) :
			(grep {$prev_sign =~ /^$_$/} @{$self->{grammar}{logic_or}})
		) {
			if (grep {$sign =~ /^$_$/} @{$self->{grammar}{end_of_statement}}) { $prev_sign = $sign; }
			next;
		}
		else {
			$self->{exec_error} = 0;
			$prev_sign = $sign;
			my $tree = $self->{StringParser}->parse($string, 'pipe_gram'); # print "Debug: ".Dumper($tree);
			if ($self->{StringParser}->{error}) {
				$self->print("Parsing error: ".$self->{StringParser}->{error}, 'error');
				$self->{exec_error} = 1;
			}
			else {
				if ($#{$tree} > 0) {
					unless ($self->{objects}{Trog} ) {
						$self->print("Syntax to advanced, use a Trog object for this kind of stuff.", 'error');
						$self->{exec_error} = 1;
					}
					elsif ( grep {($_->[2] ne 'SYSTEM') && ($_->[2] ne 'PERL')} @{$tree} ) {
						$self->print("Syntax to advanced, wait for a future release.", 'error');
						$self->{exec_error} = 1;
					}
					else { return $self->Trog->parse($tree); }
				}
				else { $re = $self->parse_block($tree->[0][0], $tree->[0][2]); }
			}
		}
	}
    POSIX::tcsetpgrp(0,getpgrp);
	return $re;
}

sub parse_block {
	my $self = shift;
	my ($string, $context) = @_; 
	$self->print("string: \'$string\' context: \'$context\'", 'debug');

	if (ref($self->{grammar}{context}{$context}) && $self->{grammar}{context}{$context}[0]) {
		my $sub = $self->{grammar}{context}{$context}[0];
		$string =~ s/'/\\'/g; # put safety escape on
		my @dus = ('\''.$string.'\'');
		if ($sub =~ /(\(.*\))\s*$/) {
			push @dus, eval($1);
			$sub =~ s/(\(.*\))\s*$//;
		}
		my $eval_string = '$self->'.$sub.'('.join(',', @dus).')';
		$self->print("Going to call: \'$eval_string\'", 'debug');
		my $re = [ eval($eval_string) || '' ];
		if ($@) {
			$self->{exec_error} = 1;
			$self->print('Your spinal fin seems to be missing: '.$@, 'error');
		}
		return $re;
	}
	elsif ($context eq 'PERL') {
		my $re = $self->eval_zoid('no strict;'.$string);
		$self->print("\n", '', 1); # force printing a '\n' -- dirty hack
		return $re;
	}
	elsif ($context eq 'ZOID') { return $self->eval_zoid($string); }
	elsif ($context eq 'SYSTEM') { return $self->eval_system($string); }
	else { $self->print("This should never happen. Is there nothing we can do for $context?", 'error'); }
	return "";
}

sub eval_zoid { # use long var names to keep namspace as clean as possible
	my $self = shift;
	my $eval_code_string = shift;
	my $parse_tree = $self->{StringParser}->parse($eval_code_string, 'eval_zoid_gram');
	#print "Debug: ".Dumper($tree);
	foreach my $ref (@{$parse_tree}) {
		if ($ref->[1] eq "\x1E_") { $ref->[1] = '$self->{exec_topic}'}
		elsif ($ref->[1] =~ s/^(->|(\x1E))//) {
			if ($self->{core}{show_naked_zoid} && !($1 eq $2)) { $ref->[1] = '$self->'.$ref->[1]; }
			elsif (grep {$_ eq $ref->[1]} @{$self->clothes}) { $ref->[1] = '$self->'.$ref->[1]; }
			elsif ($ref->[1] =~ m|^\{(\w+)\}$|) { $ref->[1] = '$self->{vars}'.$ref->[1]; }
			else { $ref->[1] ='$self->object(\''.$ref->[1].'\')'; }
		}
	}
	$eval_code_string = join('', map {$_->[0].$_->[1]} @{$parse_tree});
	$self->print("Going to eval: \'$eval_code_string\'", 'debug');
	$_ = $self->{exec_topic};
	my $return_value = [ eval ($eval_code_string) || '' ];
	$self->{exec_topic} = $_;
	if ($@) {
		$self->{exec_error} = 1;
		$self->print('Bwubububu buuuu: '.$@, 'error');
	}
	return $return_value;
}

sub eval_system {
	my $self = shift;
	my $string = shift;
	$string =~ m/^\s*(.*?)\s*$/;
	my @args = map {$_->[0]} @{$self->{StringParser}->parse($1, 'space_gram')};
	if ( $self->is_executable($args[0]) ) {
		my $bin = shift @args;
		my @exp_args = ();
		for (@args) {
			$_ =~ s/\x{1E}_/$self->{exec_topic}/;
			if ($_ =~ /[^\w\s\\\/\.]/) { push @exp_args, @{$self->Intel->expand_files($_)} }
			else { push @exp_args, $_; }
		}
		@exp_args = map {s/\\//g; $_} @exp_args;
		$self->print("Going to system: ( \'$bin\', \'".join('\', \'', @exp_args)."\')", 'debug');
		$self->{exec_error} = system($bin, @exp_args);
		$self->{exec_topic} = @exp_args ? $exp_args[-1] : $ENV{PWD};
	}
	else {
		$self->print("No such executable: $args[0]", 'error');
		$self->{exec_error} = 1;
	}
	return "";
}

#######################
#### information routines ####
#######################

sub list_objects {
	my $self = shift;
	return [sort(keys(%{$self->{objects}}))];
}

sub object {
	my $self = shift;
	my $name = shift;
	my $silence_bit = shift;

	if ($self->{objects}{$name}) { return $self->{objects}{$name}; } #speed is vital
	elsif (my ($ding) = grep {lc($_) eq lc($name)} keys %{$self->{objects}}) { return $self->{objects}{$ding}; }
	elsif (($ding) = grep {lc($_) eq lc($name)} @{$self->{core}{core_objects}}) { # use stub
		my $pack = "stub_".lc($ding);
		$self->{objects}{$ding} = $pack->new($self);
		return $self->{objects}{$ding};
	}

	unless ($silence_bit) {
		my @caller = caller;
		$self->print("No such object \'$name\' as requested by ".$caller[0]." line ".$caller[2], 'error');
	}
	return 0;
}

sub test_object {
	my $self = shift;
	my $zoidname = shift;
	my $class = shift || '';
	if (my $ding = $self->object($zoidname, 1)) { if (ref($ding) =~ /$class$/) { return 1; } }
	return 0;
}

sub list_aliases {
	my $self = shift;
	return $self->{grammar}{aliases};
}

sub clothes {
	my $self = shift;
	my @return = map {'{'.$_.'}'} @{$self->{core}{clothes}{keys}};
	push @return, @{$self->{core}{clothes}{subs}};
	return [@return];
}

sub list_clothes { # includes $self->{vars}
	my $self = shift;
	my @return = map {'{'.$_.'}'} sort @{$self->{core}{clothes}{keys}};
	push @return, map {'{'.$_.'}'} sort keys %{$self->{vars}};
	push @return, sort @{$self->{core}{clothes}{subs}};
	return [@return];
}

#################
#### Output subs  ####
##################

sub print {
	my $self = shift;
	my $ding = shift;
	my $type = shift || 'output';
	my $options = shift; # options: m => markup, n => no_newline, s => sql =>array of arrays of scalars formatting
	my $succes = 0;
	unless ($self->{core}{silent}{$type}) {
		my $fh = select; # backup filehandle
		
		if ($type eq 'error') {
			select STDERR;
		}

		my $colored = 1;
		if ($self->{core}{print}{colors}{$type}) { print color($self->{core}{print}{colors}{$type}); }
		elsif (grep {$_ eq $type} @{$self->{grammar}{ansi_colors}}) { print color($type); }
		else { $colored = 0; }

		if (($options =~ m/m/)||(grep {$_ eq $type} @{$self->{core}{print}{mark_up}})) { print "## ".uc($type).": "; }

		if (($options =~ m/s/) && (ref($ding) eq 'ARRAY')) { $succes = $self->Buffer->print_sql_list(@{$ding}); }
		elsif ((ref($ding) eq 'ARRAY') && !(grep {ref($_)} @{$ding})) {
			if ($#{$ding} == 0) {
				unless ($options =~ m/n/) { $ding->[0] =~ s/\n?$/\n/; }
				$succes = print $ding->[0];
			}
			else { $succes = $self->Buffer->print_list(@{$ding}); }
		}
		elsif (ref($ding)) {
			my $string = Dumper($ding);
			$string =~ s/^\s*\$VAR1\s*\=\s*//;
			$succes = print $string
		}
		else {
			unless ($options =~ m/n/) { $ding =~ s/\n?$/\n/; }
			$succes = print $ding;
		}

		if ($colored) { print color('reset'); }
		select $fh;
	}
	return $succes;
}

sub ask {
	my $self = shift;
	if ($self->{objects}{Buffer}) {
		return $self->{objects}{Buffer}->read_question($_[0]);
	}
	else {
		unless (ref($_[0])) {
			my $string = $_[0];
			print $string;
			my $dus = <STDIN>;
			chomp $dus;
			return $dus;
		}
	}
}

########################################
#### File routines -- do they belong in this object ? ####
########################################

sub abs_path {
	# return absolute path
	# argument: string optional: reference
	my $self = shift;
	my $string = shift || return $ENV{PWD};
	my $refer = $_[0] ? $self->abs_path(shift @_) : $ENV{PWD}; # possibly recurs
	$refer =~ s/\/$//; # print "debug: refer was: $refer\n"; #/
	if ($string =~ /^\//) {} # do nothing
	elsif ( $string =~ /^~([^\/]*)/ ) {# print "debug: '~': ";
		if ($1) {
			my @info = getpwnam($1); # Returns ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell).
			$string =~ s/^~$1\/?/$info[7]\//;
		}
		else { $string =~ s/^~\/?/$ENV{HOME}\//; }
	}
	elsif ( $string =~ s/^\.(\.+)(\/|$)//) {  #print "debug: '../': string: $string length \$1: ".length($1)." "; #'
		my $l = length($1);
		$refer =~ s/(\/[^\/]*){0,$l}$//;  #print "refer: $refer\n"; #/
		$string = $refer.'/'.$string;
	}
	else {	# print "debug: './': ";
		$string =~ s/^\.(\/|$)//; # print "string: $string refer: $refer\n"; #/
		$string = $refer.'/'.$string;
	}
	$string =~ s/\\//g;# print "debug: result: $string\n"; #/
	return $string;
}

sub cache_path {
	my $self = shift;
	my $ding = shift;
	if ($ding eq "force") { $self->print("Reloading path..", 'message', 'n'); }
	elsif ($ding eq "init") { $self->print("Caching path..", 'message', 'n'); }
	@{$self->{cache}{path_dirs}} = grep {-e $_} grep {($_ ne '..') && ($_ ne '.')} split (/:/, $ENV{PATH});
	foreach my $dir (@{$self->{cache}{path_dirs}}) {
		if ($ding) { $self->print(".", 'message', 'n'); }
		if ($ding eq "force") { $self->scan_dir($dir, "force", 1); }
		else {$self->scan_dir($dir, '', 1);}
	}
	if ($ding) { $self->print(".", 'message'); }
}

sub list_path {
	my $self = shift;
	my @return = ();
	foreach my $dir (@{$self->{cache}{path_dirs}}) { push @return, grep {-x $dir.'/'.$_} @{$self->{cache}{dirs}{$dir}{files}}; }
	return [@return];
}

sub scan_dir {
	my $self = shift;
	my $dir = shift || $ENV{PWD};
	my ($string, $no_wipe) = @_;
	unless ($self->{cache}{dirs}{$dir}) { $dir = $self->abs_path($dir); }
	my $mtime = (stat($dir))[9];
	unless ($self->{cache}{dirs}{$dir} && ($string ne 'force') && ($mtime == $self->{cache}{dirs}{$dir}{mtime})) {
		$self->read_dir($dir, $no_wipe);
	}
	else { $self->{cache}{dirs}{$dir}{cache_time} = time; }
	return $self->{cache}{dirs}{$dir};
}

sub read_dir {
	my $self = shift;
	my $dir = shift;
	if (-e $dir) {
		my $no_wipe = shift || $self->{cache}{dirs}{$dir}{no_wipe};
		opendir DIR, $dir;
		my @contents = readdir DIR;
		splice(@contents, 0, 2); # . && ..
		closedir DIR;
		chdir $dir;
		my @files = grep {-f $_ || -f readlink($_)} @contents;
		my @dirs = grep {-d $_  || -d readlink($_)} @contents;
		my @rest = grep { !(grep $_, @files) && !(grep $_, @dirs) } @contents;
		chdir($ENV{PWD});
		$self->{cache}{dirs}{$dir} = { 
			'files' => [@files],
			'dirs' => [@dirs],
			'rest' => [@rest],
			'mtime' => (stat($dir))[9],
			'no_wipe' => $no_wipe,
			'cache_time' => time,
		};
	}
}

sub is_executable {
	my $self = shift;
	my $name = shift;
	if (-x $name) { return 1; }
	elsif (grep {/^$name$/} @{$self->list_path}) { return 1; }
	else {return 0; }
}

sub wipe_cache {
	my $self = shift;
	foreach my $dir (keys %{$self->{cache}{dirs}})  {
		unless ($self->{cache}{dirs}{$dir}{no_wipe}) {
			my $diff = $self->{cache}{dirs}{$dir}{cache_time} - time;
			if ($diff > $self->{core}{cache_time}) { delete ${$self->{cache}{dirs}}{$dir}; }
		}
	}
}

#####################
#### some functions ####
######################

sub silent {
	my $self = shift;
	my $option = shift;
	$self->{core}{silent}{message} = 1;
	$self->{core}{silent}{warning} = 1;
	if ($option eq 'no_roundup') { $self->{core}{round_up} = 0; }
}

sub exit {
	my $self = shift;
	$self->{core}{continu} = 0;
}

sub reload {
    my $self = shift;
    local $^W=0;
    map {eval "do '$_'"} values %INC;
    $self->print("reloaded \%INC", 'message');
}

sub dev_null {} # does absolutely nothing

#####################
#### Event logic ####
#####################

sub broadcast_event {
	my $self = shift;
	my $event = shift;
	map {$self->{objects}{$_}->event($event, @_)} @{$self->{events}{$event}};
}

sub register_event {
    my $self = shift;
    my $event = shift;
    my $object = shift; # zoid name
    unless (exists $self->{events}{$event}) { $self->{events}{$event} = [] }
    push @{$self->{events}{$event}}, $object;
}

sub registered_events {
    my $self = shift;
    my $object = shift; # zoid name
    my @events;
    foreach my $event (keys %{$self->{events}}) {
        if (grep {$_ eq $object} @{$self->{events}{$event}}) { push @events, $event; }
    }
    return @events;
}

sub registered_objects {
    my $self = shift;
    my $event = shift;
    return @{$self->{events}{$event}};
}

sub unregister_event {
    my $self = shift;
    my $event = shift;
    my $object = shift;
    @{$self->{events}{$event}} = grep {$_ ne $object} @{$self->{events}{$event}};
}

sub unregister_all_events {
	my $self = shift;
	my $object = shift;
	foreach my $event (keys %{$self->{events}}) {
		@{$self->{events}{$event}} = grep {$_ ne $object} @{$self->{events}{$event}};
	}
}

###############################
#### filthy magic-loader:) ####
###############################

sub init_postponed {
	my $self = shift;
	#print "debug postponed init got : ".join("--", @_)."\n";
	my $zoidname = shift;
	my $class = shift;

	unless ($self->use_postponed($class)) { return 0; }

	if ($class->can('isFish') && $class->isFish) {
		unless ($self->{config}{$zoidname}) { $self->{config}{$zoidname} = {}; }
		$self->{objects}{$zoidname} = $class->new($self, $self->{config}{$zoidname}, $zoidname);
		$self->{objects}{$zoidname}->init(@_);
	}
	elsif ($class->can('new')) { $self->{objects}{$zoidname} = $class->new(@_); }
	else { $self->print('This class is not truly OO - wait for future release.', 'error'); }

	return 1;
}

sub use_postponed {
    my $self = shift;
    my $mod = shift;
    $mod =~ s{::}{/}g; #/
    unless ($INC{"$mod.pm"}) {
        if (defined(eval "require '$mod.pm'")) { return 1; }
        else {
            $self->print("Failed to include $mod.pm: ",$@);
            return 0;
        }
    }
}

#########################
#### Some more magic ####
#########################

sub round_up {
	my $self = shift;
	if ($self->{round_up}) {
		foreach my $n (keys %{$self->{objects}}) {
			#print "debug roud up: ".ref( $self->{objects}{$n})."\n";
			if ($self->{objects}{$n}->can('isFish') && $self->{objects}{$n}->isFish) {
				$self->{objects}{$n}->round_up;
			}
		}
	}
	$self->{rounded_up} = 1;
	$self->print("# ### CU - Please fix all bugs !! ### #  ", 'message');
	#print "Debug: exit status: ".$self->{exec_error}."\n";
	return $self->{exec_error};
}

sub AUTOLOAD {# print "Debug: autoloader got: ".join('--', @_)." autoload: $AUTOLOAD\n";
    my $self = shift;
    my $method = shift || (split/::/,$AUTOLOAD)[-1];

    if ( $self->object($method, 1) ) {
	($method) = grep {lc($_) eq lc($method)} keys %{$self->{objects}};
	my $sub = sub {
		my $self = shift;
		if ($self->{objects}{$method}) { return $self->{objects}{$method}; } # speed is vital
		else { return $self->object($method); }
	};
	no strict 'refs';
	*{ref($self)."::".$method}=$sub;
	$self->$sub(@_);
    }
    else {
	my @caller = caller;
	$self->print("failed to AUTOLOAD $method as requested by ".$caller[0]." line ".$caller[2], 'error');
	return;
    }
}

sub DESTROY {
	my $self = shift;
	unless ($self->{rounded_up}) { $self->round_up; } # something went wrong -- unsuspected die
}

package stub_stub;
sub new {
	my $class = shift;
	my $self = {};
	$self->{parent} = shift;
	bless $self, $class;
}
sub help { return "This is a stub object -- it can't do anything."; }

package stub_prompt;
use base 'stub_stub';
sub stringify { return 'Zoidberg no-prompt>'; }
sub getLength { return length('Zoidberg no-prompt>'); }

package stub_buffer;
use base 'stub_stub';
sub read { $/ = "\n"; print 'Zoidberg no-buffer> '; return <STDIN>; }
sub read_question { $/ = "\n"; print $_[1]; return <STDIN>; }
sub print_list { shift; print join("\n", @_)."\n"; }
sub print_sql_list { shift; print join("\n", map {join(', ', @{$_})} @_)."\n"; }
sub size { return (80, 160); } # width and heigth in chars

package stub_history;
use base 'stub_stub';
sub add_history {}
sub get_hist { return (undef, '', 0); }
sub del_one_hist {}

package stub_commands;
use base 'stub_stub';
sub parse {
	if ($_[1] eq 'quit') { $_[0]->c_quit; }
	return "";
}
sub list { return ['quit']; }
sub c_quit {
	my $self = shift;
	if ($_[0]) {$self->{parent}->print($_[0]) }
	$self->{parent}->History->del_one_hist; # leave no trace
	$self->{parent}->exit;
}

package stub_intel;
use base 'stub_stub';
sub tab_exp { return [0, [$_[1]]]; }

package stub_help;
use base 'stub_stub';
sub help { print "No help available.\n" }
sub list { return []; }

package stub_motz;
use base 'stub_stub';
sub fortune { return ''; }

#more stubs ?

1;

__END__

=pod

=head1 NAME

Zoidberg - a modular perl shell

=head1 SYNOPSIS

You most likely want to use the default config files as installed
by the ProgramFiles package and all the modules from the Zoidberg
package.


  use Zoidberg;

  # set config
  my $fluff_conf = {
    'prefix'       => '/usr/local',	
    # $prefix/share/zoid/... expected to exist
    'config_dir'   => '/home/my_user/.zoid',
    'config_file'  => 'profile.pd',
    'core_file'    => 'core.pd',
    'grammar_file' => 'grammar.pd',
  };

  # create and init parent object
  my $cube = Zoidberg->new;
  $cube->init($fluff_conf);
  
  # start interactive mode
  $cube->main_loop;
  
  # exit nicely
  my $exit = $cube->round_up ? 1 : 0;
  exit $exit;


=head1 PROJECT

Zoidberg provides a shell written in perl, configured in perl and operated in perl.
It is intended to be a replacement for bash in the future, but that is a long way.
Most likely you will have to be a perl programmer or developer to enjoy this.

=head1 DESCRIPTION

This class provides a parent object in charche of a whole bunch of
plugins. Most of the real functionality is put in this plugins.
Also this class is in charche of broadcasting events.
Stubs are provided for core plugins.
This class autoloads plugin names as subroutines.

=head2 EXPORT

None by default.

=head1 METHODS

Some usefull methods:

=over 4

=item B<new()>

  Simple constructor

=item B<init(\%config)>

  Initialize secondary objects and set config

=item B<main_loop()>

  Spans interactive shell reading from secondary object 'Buffer' or from STDIN.

=item B<list_objects()>

  List secondary objects.

=item B<object($zoidname)>

  Returns secondary object stored under $zoidname.

=item B<test_object($zoidname, $class)>

  Returns true if object $zoidname exists and is blessed as $class

=item B<list_aliases()>

  List aliases in grammar -- used to generate help function

=item B<print($ding, $type, $options)>

  USE this in secondary objects !

  Fancy print function -- used by plugins to print instead of
  perl function "print"
  It uses Data::Dumper for complex data

  $ding can be ref or string of any kind
  $type can be any string and is optional
     examples are: "debug", "message", "warning" and "error"
  $type also can be an ansi color.
  $options is an string containing chars as option switches
	n : put no newline after string
	m : force markup
	s : data is ref to array of arrays of scalars -- think sql records

=item B<ask($question)>

  Does a read with $question as prompt -- returns answer

=item B<abs_path($file, $reference)>

  Returns the absolute path for possible relative $file
  $reference is optional an defaults to $ENV{PWD}

=item B<scan_dir($dir)>

  Returns contents of $dir as a hash ref containing :
	'files' => [@files],
	'dirs' => [@dirs],
	'rest' => [@rest],
  'rest' are all files that are not (a symlink to) a file or dir

=item B<exit()>

  Called by plugins exit zoidberg -- this end a main_loop loop

=item B<broadcast_event($$event_name, @args)>

  Let all who are interrested know that event $event has taken place
  under conditions @args

=item B<register_event($event_name, $zoid_name)>

  register object $zoid_name for event $event_name

=item B<unregister_event($event_name, $zoid_name)>

  unregister object $zoid_name for event $event_name

=item B<registered_events($zoid_name)>

  list events for object $zoid_name

=item B<registered_objects($event_name)>

  list objects for event $event_name

=item B<unregister_all_events($zoid_name)>

  unregister object $zoid_name for all events

=item B<init_postponed($zoidname, $class, @args)>

  initialise a secundary object under name $zoidname of class $class
  and with arguments @args

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

E<lt>http://zoidberg.sourceforge.netE<gt>

=cut

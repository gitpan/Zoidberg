package Zoidberg;

our $VERSION = '0.04';

our $LONG_VERSION =
" Zoidberg - a modular perl shell, version $VERSION
 Copyright (C) 2002 J.G.Karssenberg and R.L.Zwart.
 Visit http://zoidberg.sourceforge.net for more information";

use strict;
use vars qw/$AUTOLOAD/;
use Term::ANSIColor;
use Data::Dumper;
use Safe;
use Zoidberg::PdParse;

push @Zoidberg::ISA, ("Zoidberg::PdParse");

sub new {
	my $class = shift;
	my $self = {};

	$self->{core}  = {};		# global configuration
	$self->{grammar} = {};		# parsing configuration
	$self->{cache}	= {};		# cache - TODO non caching option (?)
	$self->{events} = {};		# hash used for broadcasting events
	$self->{objects} = {};		# plugins as blessed objects
	$self->{config} = {};		# plugin configuration
	$self->{pending} = [];	# pending commands

	$self->{core} = {
		'silent' => {
			'output' => 0,
			'warning' => 0,
			'error' => 0,
			'message' => 0,
			'debug' => 1,
		},
		'core_objects' => [qw/Buffer Intel Prompt Commands History/],
		'non_core_keys' => [qw/core grammar config/],
	};
	$self->{round_up} = 1;
	$self->{exec_error} = 0;
	$self->{cache}{max_dir_hist} = 10; # moet nog weg
	# these have stub versions

	bless($self, $class);
}

sub init {
	my $self = shift;

	# print welcome message
	$self->print("  ## Welcome to the Zoidberg shell Version $VERSION ##  ", 'message');

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
		if ($data->[1]) {
			if (ref($data->[1]) eq 'ARRAY') { @args = @{$data->[1]}; }
			else { @args = ($data->[1]); }
		}

		my $class = $data->[0];
        	unless ($self->use_postponed($class)) { next; }

		if ($class->can('isFish') && $class->isFish) {
			unless ($self->{config}{$zoidname}) { $self->{config}{$zoidname} = {}; }
			$self->{objects}{$zoidname} = $class->new($self, $self->{config}{$zoidname}, $zoidname);
			$self->{objects}{$zoidname}->init(@args);
		}
		else { $self->{objects}{$zoidname} = $class->new(@args); }

		if ($data->[2]) { eval($data->[2]); }
	}

	# init self
	$self->cache_path('init');
	$self->{StringParser} = Zoidberg::StringParse->new($self->{grammar}, 'pending_gram');
    	$self->MOTZ->fortune;
	$self->print("  ## Type help to view commands and objects", 'message');
}

########################
#### main parsing routines ####
########################

sub main_loop {
	#return: boolean -- if 1 continue if 0 die
	my $self = shift;
	$self->{core}{continu} = 1;
	$self->{rounded_up} = 0;
	while ($self->{core}{continu}) {
		$self->{exec_error} = 0;

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

sub parse {
	my $self = shift;
	my @pending = ();
	for (@_) {
		push @pending, map {$_->[0]} @{$self->{StringParser}->parse($_)};
		if ($self->{StringParser}->{error}) {
			$self->print("Syntax error.", 'error');
			return "";
		}
	}
	my ($re, $i) = ("", 0);
	for (@pending) { $i++;
		my $logic_tree = $self->{StringParser}->parse($_, 'logic_gram');
		if ($self->{StringParser}->{error}) {
			$self->print("Syntax error in block $i.", 'error');
			return "";
		}
		$self->{exec_error} = 0;
		#print "debug: ".Dumper($logic_tree);
		while (@{$logic_tree}) {
			my ($string, $sign) = @{shift @{$logic_tree}};
			$re = $self->basic_parser($string);
			if ($sign eq '||') { unless ($self->{exec_error}) { return $re; } }
			elsif ($sign eq '&&') { if ($self->{exec_error}) { return $re; } }
		}
	}
	return $re;
}

sub basic_parser {
	my $self = shift;
	my $string = shift;

	my $tree = $self->{StringParser}->parse($string, 'pipe_gram');
	if ($self->{StringParser}->{error}) {
		$self->print("Syntax error.", 'error');
		return "";
	}

	if ($#{$tree} > 0) {
		unless ($self->{objects}{Trog} ) {
			$self->print("Syntax to advanced, use a Trog object for this kind of stuff.", 'error');
			return "";
		}
		elsif ( grep {$_->[2] eq 'ZOID'} @{$tree} ) {
			$self->print("Syntax to advanced, wait for a future release.", 'error');
			return "";
		}
		else { return $self->Trog->parse($tree); }
	}

	my $context = $tree->[0]->[2];
	if ($context eq 'PERL') {
		$tree->[0]->[0] =~ m/^\s*\{(.*)\}\s*$/;
		my $string = $1;
		#print "debug: trying to eval --$string--\n";
		if ($self->{objects}{Safe}) {
			my $re = $self->{objects}{Safe}->reval($string);
			print "\n";	# else the prompt could overwrite some printed data - more fancy solution in buffer?
			return $re;
		}
		else { #print "debug: no Safe object\n";
			my $re = eval { eval($string) };
			unless ($@) {
				print "\n";	# idem
				return $re;
			}
			else {
				$self->print($re);
				$self->{exec_error} = 1;
				return "";
			}
		}
	}
	elsif ($context eq 'ZOID') {
		my @args = map {$_->[0]} @{$self->{StringParser}->parse($tree->[0]->[0], 'space_gram')};
		while ($args[0] !~ /\w/) { shift @args; }
		my $string = shift(@args);
		if ($self->{core}{show_core}) { $string =~ s/^(->)?/\$self->/; }
		elsif ($string =~ /^(->)?\{(\w*)\}/) {
			if (grep {$_ eq $2} @{$self->{core}{non_core_keys}}) { $string =~ s/^(->)?/\$self->/; }
			else {
				$self->print("Turn on the \'show_core\' bit to see Zoibee naked.", 'error');
				$self->{exec_error} = 1;
				return "";
			}
		}
		else { $string =~ s/^(->)?(\w+)/\$self->object\(\'$2\'\)/; }
		my $args = '';
		if ($string =~ /\((.*?)\)$/) {
			$string =~ s/\((.*?)\)$//;
			$args = $1.', ';
		}
		if (@args) { $args .= '\''.join('\', \'', @args).'\''; }
		if ($args) { $string .= '('.$args.')'; }
		#print "debug: going to eval string: $string\n";
		my $re = eval($string);
		unless ($@) {return $re; }
		else {
			$self->print($@);
			$self->{exec_error} = 1;
			return "";
		}
	}
	elsif ($context eq 'SYSTEM') {
		$tree->[0]->[0] =~ m/^\s*(.*?)\s*$/;
		if ($1) {
			my @args = map {$_->[0]} @{$self->{StringParser}->parse($1, 'space_gram')};
			$self->{exec_error} = system(@args);
		}
		else { return ""; }
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
	elsif (($ding) = grep {lc($_) eq lc($name)} @{$self->{core}{core_objects}}) {
		my $pack = "stub_".lc($ding);
		$self->{objects}{$ding} = $pack->new($self);
		return $self->{objects}{$ding};
	}

	unless ($silence_bit) {
		my @caller = caller;
		$self->print("No such object \'$name\' as requested by ".$caller[0]." line ".$caller[2], 'error');
		return;
	}
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
	return [keys %{$self->{grammar}{aliases}}];
}

sub alias {
	my $self = shift;
	return $self->{grammar}{aliases}{$_[0]};
}


#####################
#### chache status subs ####
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

#################
#### Output subs  ####
##################

sub print {
	my $self = shift;
	my $ding = shift;
	my $type = shift || 'output';
	my $no_newline_bit = shift; # vunzige hack
	unless ($self->{core}{silent}{$type}) {
		my $fh = select; # backup filehandle
		if ($type eq 'error') {
			select STDERR;
		}
		if ($self->{core}{print_colors}{$type}) { print color($self->{core}{print_colors}{$type}); }
		if (grep {$_ eq $type} qw/error warning debug/) { print "## ".uc($type).": "; }

		if (ref($ding) eq 'ARRAY' && !ref($ding->[0])) { $self->Buffer->print_list(@{$ding}); }
		elsif (ref($ding)) { print Dumper($ding); }
		else {
			unless ($no_newline_bit) { $ding =~ s/\n?$/\n/; }
			print $ding;
		}
		if ($self->{core}{print_colors}{$type}) { print color('reset'); }
		select $fh;
	}

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

sub abs_path {	# TODO to intel.pm
	# return absolute path
	# argument: string optional: reference
	my $self = shift;
	my $pattern = shift || $ENV{PWD};
	my $ref = shift || $ENV{PWD};
	$pattern =~ s/^~(\/|\s|$)/$ENV{HOME}\//;
	if ($pattern =~ /^\//) { return $pattern; }
	if ( $pattern =~ /^~([^\/\s]+)/ ) {
		if ($self->{objects}{Intel}) {
			my @info = getpwnam($1); # Returns ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell).
			$pattern =~ s/^~$1\/?/$info[7]\//;
			return $pattern;
		}
	}
	if ( $pattern =~ /^[^\.]/) {$pattern = "./".$pattern};
	if ( $pattern =~ /(^|\/)\.{1,2}(\/|\s*$)/ ) {	# match ^./ ^../ /./ /../ .. . etc
		my @guide = split(/\//, $pattern);
		my @abs = split(/\//, $ref);
		foreach my $ding (@guide) {
			unless (($ding eq ".") || ($ding eq "")) {
				if ($ding eq "..") { pop(@abs); }
				else { push @abs, $ding; }
			}
		}
		$pattern = join("/", @abs);
	}
	$pattern =~ s/\/\s*$//;		#/ comment om mn highlighting te fixen :(

	return $pattern;
}

sub cache_path {
	my $self = shift;
	my $ding = shift;
	if ($ding eq "force") { $self->print("Reloading path..", 'message', 1); }
	elsif ($ding eq "init") { $self->print("Caching path..", 'message', 1); }
	@{$self->{cache}{path_dirs}} = grep {-e $_} grep {($_ ne '..') && ($_ ne '.')} split (/:/, $ENV{PATH});
	foreach my $dir (@{$self->{cache}{path_dirs}}) {
		if ($ding) { $self->print(".", 'message', 1); }
		if ($ding eq "force") { $self->scan_dir($dir, "force", 1); }
		else {$self->scan_dir($dir, '', 1);}
	}
	if ($ding) { $self->print(".", 'message'); }
}

sub list_path {
	my $self = shift;
	my @return = ();
	foreach my $dir (@{$self->{cache}{path_dirs}}) { push @return, @{$self->{cache}{dirs}{$dir}{files}}; }
	return [@return];
}

sub scan_dir {
	my $self = shift;
	my ($dir, $string, $no_wipe) = @_;
	$dir = $self->abs_path($dir);
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
	my $name = shift;
	my $class = shift;
	#print "debug : going to init: $n - config: ".Dumper($config->{$n});
	if ($self->use_postponed($class)) {
		my $oconfig = $self->{cache}{config_backup}{$name} || {};
		$self->{objects}{$name} = $class->new(@_);
		if (($class =~ /Zoidberg/)&&($class->can('init'))) { $self->{objects}{$name}->init($self, $oconfig); }
		# only use init for residential modules
		return 1;
	}
}

sub use_postponed {
    my $self = shift;
    my $mod = shift;
    $mod =~ s{::}{/}g; #/
    return $self->inc($mod);
    #my @trappen = split/\//,$mod;
    #for (my$i=0;$i<=$#trappen;$i++) {
    #    $self->inc(join('/',@trappen[0..$i]));
    #}
}

sub included {
    my $self = shift;
    my $mod = shift;
    unless ($INC{"$mod.pm"}) {
        return 0;
    }
    return 1;
}

sub inc {
    my $self = shift;
    my $mod = shift;
    unless ($self->included($mod)) {
        if (defined(eval "require '$mod.pm'")) {
            return 1;
        }
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
	$self->print("  # ### CU - Please fix all bugs !! ### #  ", 'message');
	#print "Debug: exit status: ".$self->{exec_error}."\n";
	return $self->{exec_error};
}

sub AUTOLOAD {
    my $self = shift;
    my $method = shift || (split/::/,$AUTOLOAD)[-1];

    if ( $self->object($method, 1) ) {
	($method) = grep {lc($_) eq lc($method)} keys %{$self->{objects}};
	my $sub = sub {
		my $self = shift;
		if ($self->{objects}{$method}) { return $self->{objects}{$method}; }
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
sub print_list { print join("\n", @_)."\n"; }

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

=head1 NAME

Zoidberg - a modular perl shell

=head1 SYNOPSIS

You most likely want to use the default config files as installed
by the ProgramFiles package and all the modules from the Zoidberg
package.

  use Zoidberg;

  # set config
  my $fluff_conf = {
    'prefix' => '/usr/local',	# $prefix/share/zoid/... expected to exist
    'config_dir' => '/home/my_user/.zoid',
    'config_file' => 'profile.pd',
    'core_file' => 'core.pd',
    'grammar_file' => 'grammar.pd',
  };

  my $cube = Zoidberg->new;
  $cube->init($config);
  $cube->main_loop;
  $cube->round_up;

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

=head2 new()

  Simple constructor

=head2 init(\&meta_config)

  Initialize secondary objects and set config

=head2 list_objects()

  List secondary objects

=head2 main_loop()

  Not really a loop -- does main action

=head2 print()

  Print to stdout -- USE this in secondary objects !

=head2 ask($question)

  get input

=head2 abs_path($file)

  optional: abs_path($file, $reference)
  get absolute path for file

=head2 scan_dir($dir)

  get files in dir

=head2 broadcast_event($event_name, @_)

  let all interested objects now ...

=head2 register_event($event_name, $zoid_name)

  register object $zoid_name for event $event_name

=head2 unregister_event($event_name, $zoid_name)

  unregister object $zoid_name for event $event_name

=head2 registered_events($zoid_name)

  list events for object $zoid_name

=head2 registered_objects($event_name)

  list objects for event $event_name

=head2 unregister_all_events($zoid_name)

  unregister object $zoid_name for all events

=head2 silent()

  Set Zoidberg in silent mode - for forks and background executes

=head2 exit()

  Quit Zoidberg

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

http://zoidberg.sourceforge.net

=cut

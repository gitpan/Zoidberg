package Zoidberg;

our $VERSION = '0.2a';
our $VERSION_NAME = '-mudpool-release';
our $LONG_VERSION =
"Zoidberg - a modular perl shell, version $VERSION$VERSION_NAME
Copyright (c) 2002 Jaap G Karssenberg and R.L. Zwart";
our $DEVEL = 1;

use strict;
use vars qw/$AUTOLOAD/;
use utf8;
use Data::Dumper;
use Sys::Hostname;
use Term::ANSIColor;
use POSIX qw/floor ceil/;
use Zoidberg::PdParse;
use Zoidberg::StringParse;
use Zoidberg::FileRoutines qw/:zoid_compat $cache/;

use base 'Zoidberg::ZoidParse';

our @core_objects = qw/Buffer Intel Prompt Commands History MOTZ/; # these have stub versions in this file

sub new {
	my $class = shift;
	my $self = {};

	$self->{core}		= {};	# global configuration
	$self->{grammar}	= {};	# parsing configuration
	$self->{events}		= {};	# hash used for broadcasting events
	$self->{objects}	= {};	# plugins as blessed objects
	$self->{vars}		= {};	# persistent vars
	$self->{config}		= {};	# plugin configuration
	$self->{cache}      = $cache;

	$self->{core} = { 'silent' => { 'debug' => 1, }, }; # This is a good default :)

	$self->{round_up} = 1;
	$self->{exec_error} = 0;
	$self->{_} = ''; # formely known as "exec_topic"

	bless($self, $class);
}

sub init {
	my $self = shift;

	# print welcome message
	$self->print("## This is the Zoidberg shell Version $VERSION$VERSION_NAME ##  ", 'message');

	# process fluff input
	$self->{fluff_input} = shift;
	$self->{interactive} = $self->{fluff_input}{interactive};
	for ( (grep {/_dir$/} keys %{$self->{fluff_input}}) , 'prefix') { $self->{fluff_input}{$_} =~ s/\/?$/\//; }

	$self->_init_posix; # for zoidparse

	$Zoidberg::PdParse::base_dir = $self->{fluff_input}{config_dir};
	my $pre_eval = 'my $prefix = \''.$self->{fluff_input}{prefix}.'\'; my $conf_dir = \''.$self->{fluff_input}{config_dir}.'\';';
	foreach my $name (grep {/_file$/} keys %{$self->{fluff_input}}) {
		my $file = $self->{fluff_input}{$name};
		$name =~ s/_file$//;
		if ($name eq 'cache') {
			no strict 'refs';
			${$name} = pd_read($file, $pre_eval);
		}
		else {
		    $self->{$name} = pd_merge($self->{$name}, pd_read($file, $pre_eval) );
        	}
	}

	# init various objects:
	$self->{StringParser} = Zoidberg::StringParse->new($self->{grammar}, 'script_gram');
	for (@{$self->{core}{init_objects}}) { $self->init_postponed(@{$_}); }

	# init self
	cache_path;
	if ($DEVEL) { $self->print("This is a development version -- consider it unstable.", 'warning'); }
}


########################
#### main parsing routines ####
########################

sub main_loop {
	my $self = shift;
	$self->{core}{continu} = 1;
	while ($self->{core}{continu}) {
		cache_path;
		$self->broadcast_event('precmd');

		my $cmd = eval { $self->Buffer->get_string };
		if ($@) { $self->print("Buffer died. ($@)", 'error') }
		else { 
			$self->broadcast_event('cmd', $cmd);
			$self->parse($cmd);
		}

		wipe_cache;
	}
}

sub parse {
	my $self = shift;
	return $self->trog(@_);
}

#######################
#### information routines ####
#######################

sub list_objects {
	my $self = shift;
	my %objects;
	for (keys %{$self->{core}{call_objects}}) { $objects{$_}++; }
	for (keys %{$self->{objects}}) { $objects{$_}++; }
	return [sort keys %objects];
}

sub object {
	my $self = shift;
	my $name = shift;
	my $silence_bit = shift;

	if ($self->{objects}{$name}) { return $self->{objects}{$name}; } #speed is vital
	elsif (my ($ding) = grep {lc($_) eq lc($name)} keys %{$self->{objects}}) { # match case insensitive
		return $self->{objects}{$ding};
	}
	elsif (($ding) = grep {lc($_) eq lc($name)} keys %{$self->{core}{call_objects}}) { # load on call
		$self->init_postponed($ding, $self->{core}{call_objects}{$ding});
		return $self->{objects}{$ding};
	}
	elsif (($ding) = grep {lc($_) eq lc($name)} @Zoidberg::core_objects) { # use stub
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

sub list_clothes { # includes $self->{vars}
	my $self = shift;
	my @return = map {'{'.$_.'}'} sort @{$self->{core}{clothes}{keys}};
	push @return, sort @{$self->{core}{clothes}{subs}};
	return [@return];
}

sub list_vars { return [map {'{'.$_.'}'} sort keys %{$_[0]->{vars}}]; }

#################
#### Output subs  ####
##################

sub interactivity { # TODO: save the silence state, ask jaap how to do it the RIGHT way
    my $self = shift;
    unless (-t STDOUT && -t STDIN) { $self->silent }
}

sub print {	# TODO term->no_color bitje s{\e.*?m}{}g
	my $self = shift;
    if ($self->{caller_pid}) { return $self->IPC->_call_method("$self->{caller_pid}:IPC.print",@_) }
	my $ding = shift;
	my $type = shift || 'output';
	$self->interactivity;
	my $options = shift; # options: m => markup, n => no_newline, s => sql =>array of arrays of scalars formatting
	my $succes = 0;
	unless ($self->{core}{silent}{$type}) {
		my $fh = select; # backup filehandle

		if ($type eq 'error') {
			select STDERR;
		}

		my $colored = 1;
		unless ($self->{interactive}) { $colored = 0; }
		elsif ($self->{core}{print}{colors}{$type}) { print color($self->{core}{print}{colors}{$type}); }
		elsif (grep {$_ eq $type} @{$self->{grammar}{ansi_colors}}) { print color($type); }
		else { $colored = 0; }

		if (($options =~ m/m/)||(grep {$_ eq $type} @{$self->{core}{print}{mark_up}})) { print "## ".uc($type).": "; }

		if (($options =~ m/s/) && (ref($ding) eq 'ARRAY')) { $succes = $self->print_sql_list(@{$ding}); }
		elsif ((ref($ding) eq 'ARRAY') && !(grep {ref($_)} @{$ding})) {
			if ($#{$ding} == 0) {
				unless ($options =~ m/n/) { $ding->[0] =~ s/\n?$/\n/; }
				$succes = print $ding->[0];
			}
			else { $succes = $self->print_list(@{$ding}); }
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

sub print_list {
	my $self = shift;
	my @strings = @_;
	my $width = ($self->Buffer->size)[0];
	if (!$self->{interactive} || !defined $width) { return (print join("\n", @strings)."\n"); }
	my $longest = 0;
	map {if (length($_) > $longest) { $longest = length($_);} } @strings;
	unless ($longest) { return 0; }
	$longest += 2; # we want two spaces to saperate coloms
	my $cols = floor(($self->Buffer->size)[0] / $longest);
	unless($cols > 1) { for (@strings) { print $_."\n"; } }
	else {
		my $rows = ceil(($#strings+1) / $cols);
		@strings = map {$_.(' 'x($longest - length($_)))} @strings;

		foreach my $i (0..$rows-1) {
			for (0..$cols) { print $strings[$_*$rows+$i]; }
			print "\n";
		}
	}
	return 1;
}

sub print_sql_list {
	my $self = shift;
	my $width = ($self->Buffer->size)[0];
	if (!$self->{interactive} || !defined $width) { return (print join("\n", map {join(', ', @{$_})} @_)."\n"); }
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

########################
#### some functions ####
########################

sub silent {
	my $self = shift;
	my $option = shift;
	$self->{core}{silent}{message} = 1;
	$self->{core}{silent}{warning} = 1;
	if ($option eq 'no_roundup') { $self->{core}{round_up} = 0; }
}

sub exit {
	my $self = shift;
	$self->Buffer->bell;
	$self->{core}{continu} = 0;
}

sub reload {
    my $self = shift;
    my $ding = shift;
    unless ($ding) { $ding = 'Zoidberg' }
    map {
        $self->_reload_file($INC{$_});
    } grep {-e $INC{$_}} grep /$ding/, keys %INC;
}

sub _reload_file {
    my $self = shift;
    my $file = shift;
    local($^W)=0;
    $self->print("reloading $file",'message');
    eval "do '$file'";
}

sub dev_null {} # does absolutely nothing

#####################
#### Event logic ####
#####################

sub broadcast_event {
	my $self = shift;
	my $event = shift;
	map {
		ref($_) eq 'CODE' ?
		$_->($event,@_) :
		$self->{objects}{$_}->event($event, @_)
	} @{$self->{events}{$event}};
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
    if (($class =~ /::Crab::/)&&(0)) {
        if (my $pid = $self->IPC->_locate_object($zoidname,$class)) {
            if (my $obj = $self->_generate_crab($pid,$class,$zoidname)) {
                $self->{objects}{$zoidname} = $obj;
                return 1;
            }
        }
        else {
            $class =~ s/::Crab/::Fish/;
        }
    }
    unless ($self->require_postponed($class)) { return 0; }

	if ($class->isa('Zoidberg::Fish')) {
		unless ($self->{config}{$zoidname}) { $self->{config}{$zoidname} = {}; }
		$self->{objects}{$zoidname} = $class->new($self, $self->{config}{$zoidname}, $zoidname);
		$self->{objects}{$zoidname}->init(@_);
	}
	elsif ($class->can('new')) { my $object = $class->new(@_); if(ref($object)) { $self->{objects}{$zoidname} = $object; } else { $self->print("$class->new did not return a reference, refusing to load void object", 'error');return 0 } }
	else { $self->print('This class is not truly OO - wait for future release.', 'error'); }

	return 1;
}

sub _generate_crab {
    my $self = shift;
    my $pid = shift;
    my $class = shift;
    my $zoidname = shift;
    my $str = "package $class; push\@${class}::ISA,'Zoidberg::Fish::Crab'";
    eval $str;
    if ($@) {
        $self->print("Failed to generate class $class: $!",'error');
        return;
    }
    my $obj = $class->new($self,$self->{config}{$zoidname},$zoidname,$pid);
    no strict 'refs';
    map {my$sn=$_;*{"${class}::$sn"}=sub{shift->_call($sn,@_)}} grep {!$obj->can($_)} $self->IPC->_call_method("$pid:$zoidname.methods");
    $obj;
}
 
sub require_postponed {
	my $self = shift;
	my $mod = shift;
	my $file = $mod.".pm";
	$file =~ s{::}{/}g; #/
	unless ($INC{$file}) {
		require $file || die "Failed to include \"$file\"";
	}
	1;
}

#########################
#### Some more magic ####
#########################

sub round_up {
	my $self = shift;
	if ($self->{round_up}) {
		foreach my $n (keys %{$self->{objects}}) {
			#print "debug roud up: ".ref( $self->{objects}{$n})."\n";
			if (ref($self->{objects}{$n}) && $self->{objects}{$n}->isa('Zoidberg::Fish')) {
				$self->{objects}{$n}->round_up;
			}
		}
		foreach my $name (grep {/_file$/} keys %{$self->{fluff_input}}) {
			my $file = $self->{fluff_input}{$name};
			$name =~ s/_file$//;
			if ($name eq 'cache') {
				no strict 'refs';
				pd_write($file, ${$name});
			}
			else {
				pd_write($file, $self->{$name});
			}
		}
		$self->{round_up} = 0;
		$self->print("# ### CU - Please fix all bugs !! ### #  ", 'message');
	}
	#print "Debug: exit status: ".$self->{exec_error}."\n";
	return $self->{exec_error};
}

sub AUTOLOAD {# print "Debug: autoloader got: ".join('--', @_)." autoload: $AUTOLOAD\n";
    my $self = shift;
    my $method = shift || (split/::/,$AUTOLOAD)[-1];

    #my @caller = caller;
    #print "Debug: AUTOLOAD $method as requested by ".$caller[0]." line ".$caller[2]."\n";

    if ( $self->object($method, 1) ) {
	($method) = grep {lc($_) eq lc($method)} keys %{$self->{objects}};
	my $sub = sub {
		my $self = shift;
		if ($self->{objects}{$method}) { return $self->{objects}{$method}; } # speed is vital
		else { return $self->object($method); }
	};
	no strict 'refs';
	*{ref($self)."::".$method} = $sub;
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
	if ($self->{round_up}) { # something went wrong -- unsuspected die
		$self->round_up;
		$self->print("Zoidberg was not properly cleaned up.", "error");
	}
}

package stub_stub;
sub new { bless {'parent' => $_[1]}, $_[0]; }
sub help { return "This is a stub object -- it can't do anything."; }
sub AUTOLOAD { return wantarray ? () : ''; }

package stub_prompt;
use base 'stub_stub';
sub stringify { return 'Zoidberg no prompt>'; }
sub getLength { return length('Zoidberg no prompt>'); }

package stub_buffer;
use base 'stub_stub';
sub get_string {
	$/ = "\n";
	my $prompt = $_[1] || 'Zoidberg STDIN>';
	if (ref($prompt)) { $prompt = $prompt->stringify; }
	print $prompt.' ';
	return scalar <STDIN>;
}
sub size { return (undef, undef); } # width and heigth in chars
sub bell { print "\007" }

package stub_history;
use base 'stub_stub';
sub get_hist { return (undef, '', 0); }

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
    'cache_file' => 'var/cache.pd',
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

This class provides a parent object in charge of a whole bunch of
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

R.L. Zwart, E<lt>carl0s@users.sourceforge.netE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<http://zoidberg.sourceforge.net>

=cut

package Zoidberg;

our $VERSION = '0.3a_pre1';
our $LONG_VERSION =
"Zoidberg $VERSION

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved. 
This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

http://zoidberg.sourceforge.net";
our $DEVEL = 1;

use strict;
use vars qw/$AUTOLOAD %ZoidConf/;
use utf8;
use Carp;
use Data::Dumper;
use Term::ANSIColor;
use POSIX qw/floor ceil/;
use Cwd;
use Zoidberg::Config;
use Zoidberg::PdParse;
use Zoidberg::FileRoutines qw/:engine get_dir/;
use Zoidberg::DispatchTable;
use Zoidberg::Error;

use base 'Zoidberg::ZoidParse';

our @core_objects = qw/Buffer Intel Prompt Commands History/;

our @ansi_colors = qw/
	clear rest bold underline underscore blink
	black red green yellow blue magenta cyan white
	on_black on_red on_green on_yellow on_blue
	on_magenta on_cyan on_white
/; # this also belongs in some future output package

sub new {
	my $class = shift;
	my $self = {};

	$self->{settings}	= {};	# global configuration
	$self->{events}		= {};	# hash used for broadcasting events
	$self->{objects}	= {};	# plugins as blessed objects
	$self->{vars}		= {};	# persistent vars

	$self->{settings} = { 'silent' => { 'debug' => 1, }, }; # This is a good default :)

	$self->{round_up} = 1;
	$self->{exec_error} = 0;
	$self->{_} = ''; # formely known as "exec_topic"

	bless($self, $class);
}

sub init {
	my $self = shift;
	my %input;
	if (ref($_[0]) eq 'HASH') { %input = %{shift @_} }
	else { %input = @_ }
	%{$self} = (%{$self}, %input);

	# print welcome message
	$self->print("## This is the Zoidberg shell Version $VERSION ##  ", 'message');

	Zoidberg::ZoidParse::init($self);

	# TODO hide more functions in Zoidberg::Config (for example defaults etc.)
	$self->{settings} = pd_merge($self->{settings}, Zoidberg::Config::readfile( $ZoidConf{settings_file} ) );

	# init various objects:
	$self->rehash_plugins;
	foreach my $plug (@{$self->{settings}{init_plugins}}) { 
		$self->init_object($plug) || $self->print("Could not initialize plugin '$plug'", 'error'); 
	}
	
	# init self
	my $file_cache = $ZoidConf{config_dir}.'/'.$ZoidConf{file_cache} ; # hack -- FIXME unless /^\//
	if ($file_cache && -s $file_cache) { f_read_cache($file_cache) } # FIXME -- what if this only gives the dir name ..
	else {
		$self->print("Initializing PATH cache.", 'message');
		&f_index_path;
	}
	$self->{events}{precmd} = [] unless ref($self->{events}{precmd});
	push @{$self->{events}{precmd}}, \&f_wipe_cache;
	
	if ($DEVEL) { $self->print("This is a development version -- consider it unstable.", 'warning'); }
}


# ############ #
# Main routine #
# ############ #

sub main_loop { # FIXME use @input_methods instead of buffer
	my $self = shift;
	
	$self->init_object('Buffer');
	if ($self->{objects}{Buffer}) { $self->{continue} = 1 }
	else { $self->print("Could not initialize plugin 'Buffer'", 'error') }
	
	while ($self->{continue}) {
		$self->broadcast_event('precmd');

		my $cmd = eval { $self->Buffer->get_string };
		last unless $self->{continue}; # buffer can call exit
		if ($@) {
			$self->print("Buffer died. ($@)", 'error');
			next;
		}

		$self->broadcast_event('cmd', $cmd);
		print STDERR $cmd if $self->{settings}{verbose}; # posix spec

		$self->do($cmd);

		#### Update Environment ####
		$ENV{PWD} = getcwd;
	}
}

# #################### #
# information routines #
# #################### #

sub list_objects {
	my $self = shift;
	my %objects;
	for (keys %{$self->{plugins}}) { $objects{$_}++; }
	for (keys %{$self->{objects}}) { $objects{$_}++; }
	return [sort keys %objects];
}

sub test_object {
	my $self = shift;
	my $zoidname = shift;
	my $class = shift || '';
	if (my $ding = $self->object($zoidname, 1)) { if (ref($ding) =~ /$class$/) { return 1; } }
	return 0;
}

#sub list_aliases { # DEPRECATED
#	my $self = shift;
#	return $self->{grammar}{aliases};
#}

sub list_clothes { # includes $self->{vars}
	my $self = shift;
	my @return = map {'{'.$_.'}'} sort @{$self->{settings}{clothes}{keys}};
	push @return, sort @{$self->{settings}{clothes}{subs}};
	return [@return];
}

sub list_vars { return [map {'{'.$_.'}'} sort keys %{$_[0]->{vars}}]; }

# ########### #
# Output subs #
# ########### #

# These will probably move to Zoidberg::Output or something like that

sub print {	# TODO term->no_color bitje s{\e.*?m}{}g
	my $self = shift;
	#if ($self->{caller_pid}) { return $self->IPC->_call_method("$self->{caller_pid}:IPC.print",@_) }
	my $ding = shift;
	my $type = shift || 'output';
	unless (-t STDOUT && -t STDIN) { $self->silent } # FIXME what about -p ??
	my $options = shift; # options: m => markup, n => no_newline, s => sql =>array of arrays of scalars formatting
	my ($succes, $error) = (0,0);
	unless ($self->{settings}{silent}{$type}) {

		if ($type eq 'error') { $self->print_error($ding) && return 1 }

		my $colored = 1;
		unless ($self->{interactive}) { $colored = 0; }
		elsif ($self->{settings}{print}{colors}{$type}) { print color($self->{settings}{print}{colors}{$type}); }
		elsif (grep {$_ eq $type} @ansi_colors) { print color($type); }
		else { $colored = 0; }

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
	}
	1;
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

sub print_error {
	my $self = shift;
	my $error = shift;
	if (ref($error) eq 'Zoidberg::Error') {
		return if $error->{is_printed}++;
		$error = $error->stringify(format => 'gnu') unless $error->debug;
	}
	if (ref $error) {
		$error = Dumper $error;
		$error =~ s/^\$VAR1 = /Error: /;
	}
	$error .= "\n" unless $error =~ /\n$/;
	$error = color('red') . $error . color('reset') if -t STDERR; # && niet setting no_color
	print STDERR $error;
}

# ############## #
# some functions #
# ############## #

sub silent { # FIXME -- more general solutions for switching modes
	my $self = shift;
	my $option = shift;
	$self->{settings}{silent}{message} = 1;
	$self->{settings}{silent}{warning} = 1;
	if ($option eq 'no_roundup') { $self->{settings}{round_up} = 0; }
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

# ########### #
# Event logic #
# ########### #

sub broadcast_event {
	my $self = shift;
	my $event = shift;
	for (@{$self->{events}{$event}}) {
		if (ref($_) eq 'CODE') { $_->($self, $event, @_) }
		else { $self->{objects}{$_}->event($event, @_) }
	}
}

# more glue for using events can be found in the Zoidberg::Fish class

# ############# #
# object loader #
# ############# #

sub object {
	my $self = shift;
	my $name = shift;
	my $silence_bit = shift;
	if ($self->{objects}{$name}) { return $self->{objects}{$name}; } #speed is vital
	unless ($self->{plugins}{$name}) { $self->rehash_plugins }

	if  ($self->{plugins}{$name}) { # check loadable plugins
		$self->init_object($name) 
		&& return $self->{objects}{$name};
	}
	
	if (grep {lc($_) eq lc($name)} @Zoidberg::core_objects) { # use stub
		my $pack = 'Zoidberg::stub::'.lc($name);
		$self->{objects}{$name} = $pack->new($self);
		return $self->{objects}{$name};
	}

	unless ($silence_bit) {
		my @caller = caller;
		error "No such object \'$name\' as requested by $caller[1] line $caller[2]";
	}
	return 0;
}

sub rehash_plugins { # TODO make this a command to force rehashing
	my $self = shift;
	return unless -d $ZoidConf{plugins_dir};
	my $plug_dir = get_dir($ZoidConf{plugins_dir}, 1);
	my @plugs = map {s/\.pd$//; $_} @{ $plug_dir->{files} };
	#print "debug: rehashing plugins gave me this: --".join('--', @plugs)."--\n";
	my $pre_eval = 'my $prefix = \''.$ZoidConf{prefix}.'\'; my $conf_dir = \''.$ZoidConf{config_dir}.'\';';
	foreach my $plug (@plugs) {
		unless (ref $self->{plugins}{$plug}) {
			$self->{plugins}{$plug} = pd_read($ZoidConf{plugins_dir}.$plug.'.pd', $pre_eval.qq{ my \$me = '$plug';});
			if ($self->{plugins}{$plug}{events}) { # Register events
				for (@{$self->{plugins}{$plug}{events}}) {
					unless ($self->{events}{$_}) { $self->{events}{$_} = [] }
					push @{$self->{events}{$_}}, $plug;
				}
			}
			if ($self->{plugins}{$plug}{commands}) { # Register commands
				for (keys %{$self->{plugins}{$plug}{commands}}) {
					$self->{commands}{$_} = [$self->{plugins}{$plug}{commands}{$_}, $plug];
				}
			}
			if ($self->{plugins}{$plug}{export}) {
				for (@{$self->{plugins}{$plug}{export}}) {
					$self->{commands}{$_} = [$plug.'->'.$_, $plug];
				}
			}
			unless ($self->{plugins}{$plug}{config}) { $self->{plugins}{$plug}{config} = {} }
		}
	}
									
}

sub init_object {
	my $self = shift;
	my $zoidname = shift;
	my $class = shift || $self->{plugins}{$zoidname}{module} || 'Zoidberg::stub';

#if (($class =~ /::Crab::/)&&(0)) {
#        if (my $pid = $self->IPC->_locate_object($zoidname,$class)) {
#            if (my $obj = $self->_generate_crab($pid,$class,$zoidname)) {
#                $self->{objects}{$zoidname} = $obj;
#                return 1;
#            }
#        }
#        else {
#            $class =~ s/::Crab/::Fish/;
#        }
#    }
	if ($class eq 'Zoidberg::stub') {
		$self->{objects}{$zoidname} = $class->new($self, $self->{plugins}{$zoidname}{config}, $zoidname);
		return 1;
	}
	
	unless ($self->require_postponed($class)) { return 0 }

	if ($class->isa('Zoidberg::Fish')) {
		$self->{objects}{$zoidname} = $class->new($self, $zoidname);
		$self->{objects}{$zoidname}->init(@_);
	}
	elsif ($class->can('new')) { 
		my $object = $class->new(@_); 
		if(ref($object)) { $self->{objects}{$zoidname} = $object } 
		else { 
			$self->print("$class->new did not return a reference, refusing to load void object", 'error');
			return 0;
		}
	}
	else {
		$self->print('This module seems not to be Object Oriented - wait for future release.', 'error'); 
		return 0;
	}

	return 1;
}

#sub _generate_crab {
#    my $self = shift;
#    my $pid = shift;
#    my $class = shift;
#    my $zoidname = shift;
#    my $str = "package $class; push\@${class}::ISA,'Zoidberg::Fish::Crab'";
#    eval $str;
#    if ($@) {
#        $self->print("Failed to generate class $class: $!",'error');
#        return;
#    }
#    my $obj = $class->new($self,$self->{config}{$zoidname},$zoidname,$pid);
#    no strict 'refs';
#    map { 
#    		my $sn= $_;
#		*{ "${class}::$sn" } = sub{ shift->_call($sn, @_) } 
#    } grep {!$obj->can($_)} $self->IPC->_call_method("$pid:$zoidname.methods");
#    $obj;
#}

sub require_postponed {
	my ($self, $mod) = @_;
	my $file = $mod.".pm";
	$file =~ s{::}{/}g; #/
	unless ($INC{$file}) { require $file || die "Failed to include \"$file\"" }
	1;
}

sub AUTOLOAD {# print "Debug: autoloader got: ".join('--', @_)." autoload: $AUTOLOAD\n";
    my $method = (split/::/,$AUTOLOAD)[-1];

    my @caller = caller;
    die "No such subroutine: $method on ".$caller[0]." line ".$caller[2]."\n" unless ref $_[0];
    $_[0]->print("AUTOLOAD $method as requested by ".$caller[0]." line ".$caller[2], 'debug');

    if ( $_[0]->object($method, 1) ) {
	no strict 'refs';
	*{ref($_[0])."::".$method} = sub {# hack it in the namespace
		my $self = shift;
		if ($self->{objects}{$method}) { return $self->{objects}{$method}; } # speed is vital
		else { return $self->object($method); }
	};
	goto \&{$method};
    }
    else {
	$_[0]->print("failed to AUTOLOAD $method as requested by ".$caller[0]." line ".$caller[2], 'error');
    }
}

# ############# #
# Exit routines #
# ############# #

sub exit {
	my $self = shift;
	$self->Buffer->bell;
	$self->{continue} = 0;
	# FIXME this should force the Buffer to quit
	return 0;
}

sub round_up {
	my $self = shift;
	if ($self->{round_up}) {
		foreach my $n (keys %{$self->{objects}}) {
			#print "debug roud up: ".ref( $self->{objects}{$n})."\n";
			if (ref($self->{objects}{$n}) && $self->{objects}{$n}->isa('Zoidberg::Fish')) {
				$self->{objects}{$n}->round_up;
			}
		}
		Zoidberg::ZoidParse::round_up($self);
		my $cache_file = $ZoidConf{config_dir}.'/'.$ZoidConf{file_cache};
		if ($cache_file) { f_save_cache($cache_file) } # FIXME -- see init
		$self->{round_up} = 0;
		$self->print("# ### CU - Please report all bugs ### #  ", 'message');
	}
	#print "Debug: exit status: ".$self->{exec_error}."\n";
	return $self->{exec_error};
}

sub DESTROY {
	my $self = shift;
	if ($self->{round_up}) { # something went wrong -- unsuspected die
		$self->round_up;
		$self->print("Zoidberg was not properly cleaned up.", "error");
	}
}

# ############ #
# Stub plugins #
# ############ #

package Zoidberg::stub;
sub new { bless {'parent' => $_[1], 'config' => $_[2], 'zoidname' => $_[3]}, $_[0]; }
sub help { return "This is a stub object -- it can't do anything."; }
sub AUTOLOAD { return wantarray ? () : ''; }

package Zoidberg::stub::prompt;
use base 'Zoidberg::stub';
sub stringify { return 'Zoidberg no prompt>'; }
sub getLength { return length('Zoidberg no prompt>'); }

package Zoidberg::stub::buffer;
use base 'Zoidberg::stub';
sub get_string {
	my $self = shift;
	$/ = "\n";
	my $prompt = shift || "Zoidberg $Zoidberg::VERSION STDIN >>";
	if (ref($prompt)) { $prompt = $prompt->stringify; }
	print $prompt.' ';
	if (defined (my $input = <STDIN>)) { return $input; } 
	else { $self->{parent}->exit; }
}
sub size { return (undef, undef); } # width and heigth in chars
sub bell { print "\007" }

package Zoidberg::stub::history;
use base 'Zoidberg::stub';
sub get_hist { return (undef, '', 0); }

package Zoidberg::stub::commands;
use base 'Zoidberg::stub';
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

package Zoidberg::stub::intel;
use base 'Zoidberg::stub';
sub tab_exp { return [0, [$_[1]]]; }

package Zoidberg::stub::help;
use base 'Zoidberg::stub';
sub help { print "No help available.\n" }
sub list { return []; }

1;

__END__

=head1 NAME

Zoidberg - a modular perl shell

=head1 SYNOPSIS

You most likely want to use the default config files as installed
by the ProgramFiles package and all the modules from the Zoidberg
package.

	FIXME

=head1 DESCRIPTION

This class provides a parent object in charge of a whole bunch of
plugins. Most of the real functionality is put in these plugins.
Also this class is in charche of broadcasting events.
Stubs are provided for core plugins.
This class autoloads plugin names as subroutines.

=head1 METHODS

Some usefull methods:

=over 4

=item C<new()>

Simple constructor

=item C<init(%attr)>

Initialize secondary objects and sets config. C<%attr> is merged with C<%{$self}> and is ment for 
runtime variables. System config should not be set here, but in L<Zoidberg::Config>.

=item C<main_loop()>

Spans interactive shell reading from secondary object 'Buffer' or from STDIN. To quit this loop
the routine C<exit()> of this package should be called.

=item C<list_objects()>

List secondary objects. These do not need to be loaded allready, the list is based on the config files.

=item C<object($zoidname)>

Returns secondary object stored under $zoidname. The first time this will "autoload" the object's packages and
initialise it.

=item C<test_object($zoidname, $class)>

Returns true if object $zoidname exists and is blessed as $class. Since this calls C<object($zoidname)> the object
will be initialised when tested.

=item C<print($ding, $type, $options)>

I<DEPRECATED - in time this will be moved to a package Zoidberg::Output>

I<Use this in secondary objects and plugins.> 

Fancy print function -- used by plugins to print instead of
perl function "print". It uses Data::Dumper for complex data

C<$ding> can be ref or string of any kind C<$type> can be any string and is optional.
Common types: "debug", "message", "warning" and "error". C<$type> also can be an ansi color.
C<$options> is an string containing chars as option switches.

	n : put no newline after string
	m : force markup
	s : data is ref to array of arrays of scalars -- think sql records

=item C<ask($question)>

I<DEPRECATED - in time this will be moved to a package Zoidberg::Output>

Prompts C<$question> to user and returns answer

=item C<reload($class)>

Re-read the source file for class C<$class>. This can be used to upgrade packages on runtime.
This might cause real nasty bugs when versions are incompatible.

=item C<rehash_plugins()>

Re-read config files for plugins and cache the contents. This is needed after adding a new 
plugin config file. I<When changing plugins it might not always be a "seamless upgrade".>

=item C<init_object($zoidname)>

Initialise a secundary object or plugin by the name of C<$zoidname>. This is used to 
autoload plugins. The plugin's meta data is taken from the (cached) configuration file
in the plugins dir by the same name (and the extension ".pd").

=item C<exit()>

Called by plugins exit zoidberg -- this ends a interactive C<main_loop()> loop

=item C<round_up()>

This method should be called B<before> letting the object being destroyed, it allows secundairy
objects to be cleaned up nicely. If this is forgotten, C<DESTROY> will try to do this for you
but an error will be printed to STDERR. From here all secundairy objects having
a C<round_up()> method will be called recursively.

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

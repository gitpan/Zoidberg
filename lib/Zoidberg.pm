package Zoidberg;

our $VERSION = '0.41';
our $LONG_VERSION =
"Zoidberg $VERSION

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved. 
This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

http://zoidberg.sourceforge.net";

use strict;
use vars qw/$AUTOLOAD/;
use Carp;
use Data::Dumper;
use Cwd ();
use Zoidberg::Config;
use Zoidberg::Parser;
use Zoidberg::Shell ();
use Zoidberg::PluginHash;
use Zoidberg::DispatchTable _prefix => 'dt_', 'stack';
use Zoidberg::Utils 
	qw/:error :output :fs read_data_file merge_hash :fs_engine/;
#use Zoidberg::IPC;

our @ISA = qw/Zoidberg::Parser Zoidberg::Shell/;

our %Objects; # used to store refs to ALL Zoidberg objects
our @core_objects = qw/Buffer Intel Prompt Commands History/; # DEPRECATED

sub new {
	my ($class, $self) = @_;
	$self ||= {};
	$self->{$_} ||= {} for qw/settings commands aliases events objects vars/;
	$self->{round_up}++;
	$self->{topic} ||= '';

	bless($self, $class);

	$Objects{"$self"} = $self;
	$ENV{ZOIDREF} = $self unless ref $ENV{ZOIDREF};

	## settings
	my %default = %Zoidberg::Config::settings;
	$self->{settings}{$_} ||= $default{$_} for keys %default;
	$self->{settings}{$_} || error "You should at least set a config value for $_"
		for qw/data_dirs cache_dir/;
	$self->{settings} = merge_hash( read_data_file('settings'), $self->{settings} );

	my $cache_dir = $self->{settings}{cache_dir};
	mkdir $cache_dir, 0700 || error "Could not create $cache_dir"
		unless -d $cache_dir;

	## commands
	my %commands;
	tie %commands, 'Zoidberg::DispatchTable', $self, {
		reload	=> '->reload',
		exit	=> '->exit',
		( %{$self->{commands}} )
	};
	$self->{commands} = \%commands;

	## events
	my %events;
	tie %events, 'Zoidberg::DispatchTable', $self, $self->{events};
	$self->{events} = \%events;
	$self->{events}{precmd} = sub { @ENV{qw/OLDPWD PWD/} = ($ENV{PWD}, Cwd::cwd()) };

#    $self->{ipc} = Zoidberg::IPC->new($self);
#    $self->{ipc}->init;

	## parser 
	Zoidberg::Parser::init($self);

	## plugins
	my %objects;
	tie %objects, 'Zoidberg::PluginHash', $self;
	$self->{objects} = \%objects;

	## path cache
	my $file_cache = "$cache_dir/zoid_path_cache" ;
	if (-s $file_cache) { f_read_cache($file_cache) }
	else {
		message 'Initializing PATH cache.';
		&f_index_path;
	}
	$self->{events}{precmd} = \&f_wipe_cache;

	return $self;
}

sub import { bug "You should use Zoidberg::Shell to import from" if @_ > 1 }

# ############ #
# Main routine #
# ############ #

sub main_loop { # FIXME use @input_methods instead of buffer
	my $self = shift;
	
	error "Could not initialize plugin 'Buffer'" unless $self->{objects}{Buffer};
	$self->{_continue}++;
	
	my $counter;
	while ($self->{_continue}) {
		$self->broadcast_event('precmd');

		my $cmd = eval { $self->Buffer->get_string };
		last unless $self->{_continue}; # buffer can call exit
		if ($@) {
			complain "\nBuffer died. \n$@";
			sleep 1; # infinite loop protection
			next;
		}
		else { $counter = 0 }

		$self->broadcast_event('cmd', $cmd);
		print STDERR $cmd if $self->{settings}{verbose}; # posix spec

		$self->shell_string($cmd);
	}
}

### Backward compatible temporary code ###

sub print { bug 'deprecated method, use Zoidberg::Utils qw/:output/' }

# #################### #
# information routines #
# #################### #

sub list_objects { [sort keys %{$_[0]{objects}}] }

sub test_object {
	my ($self, $zoidname, $class) = @_;
	return 1 if exists $self->{objects}{$zoidname};
	# FIXME also check class
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

# ############## #
# some functions #
# ############## #

sub silent { # FIXME -- more general solutions for switching modes
	my $self = shift;
	my $option = shift;
	$self->{settings}{output}{message} = 'mute';
	$self->{settings}{output}{warning} = 'mute';
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
	message "reloading $file";
	eval "do '$file'";
}

sub dev_null {} # does absolutely nothing

# ########### #
# Event logic #
# ########### #

sub broadcast_event { # eval to be sure we return
	my ($self, $event) = @_;
	return unless exists $self->{events}{$event};
	debug "Broadcasting event '$event'";
	for my $sub (dt_stack($self->{events}, $event)) {
		eval { $sub->($self, $event, @_) };
		complain("$sub died on event $event ($@)") if $@;
	}
}

# more glue for using events can be found in the Zoidberg::Fish class

# ########### #
# auto loader #
# ########### #

our $ERROR_CALLER;

sub AUTOLOAD {
	my $self = shift;
	my $call = (split/::/,$AUTOLOAD)[-1];

	local $ERROR_CALLER = 1;
	error "Undefined subroutine &Zoidberg::$call called" unless ref $self;
	debug "Zoidberg::AUTOLOAD got $call";

	if (exists $self->{objects}{$call}) {
		no strict 'refs';
		*{ref($self).'::'.$call} = sub { return $self->{objects}{$call} };
		goto \&{$call};
	}
	else { # Shell like behaviour
		debug 'No such object, trying to shell() it';
		@_ = ([$call, @_]); # force words parsing
		goto \&Zoidberg::Shell::shell;
	}
}

# ############# #
# Exit routines #
# ############# #

sub exit {
	my $self = shift;
	$self->Buffer->bell;
	$self->{_continue} = 0;
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
		Zoidberg::Parser::round_up($self);

		f_save_cache($self->{settings}{cache_dir}.'/zoid_path_cache');

		undef $self->{round_up};
	}
	delete $Objects{"$self"};
	return $self->{error} unless $self->{settings}{interactive}; # FIXME check this
}

sub DESTROY {
	my $self = shift;
	$self->round_up;
	warn "Zoidberg was not properly cleaned up.\n"
		if $self->{round_up};
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
use Zoidberg::Utils qw/:output/;
sub parse {
	if ($_[1] eq 'quit') { $_[0]->c_quit; }
	return "";
}
sub list { return ['quit']; }
sub c_quit {
	my $self = shift;
	if ($_[0]) { output $_[0] }
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

FIXME

=head1 DESCRIPTION

I<This page contains devel documentation, if you're looking for user documentation start with the zoid(1) man page>

This class provides an event and plugin engine.

FIXME more verbose description

=head1 METHODS

Some methods:

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

I<DEPRECATED - in time this will be moved to a package Zoidberg::Utils::Output>

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

I<DEPRECATED - in time this will be moved to a package Zoidberg::Utils::Output>

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

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

R.L. Zwart, E<lt>carl0s@users.sourceforge.netE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>
and L<http://www.gnu.org/copyleft/gpl.html>
  
=head1 SEE ALSO

L<http://zoidberg.sourceforge.net>

=cut

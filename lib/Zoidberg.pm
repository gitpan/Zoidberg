package Zoidberg;

our $VERSION = '0.42';
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

require Cwd;
require File::Glob;
require Zoidberg::Config;
require Zoidberg::Contractor;
require Zoidberg::Shell;
require Zoidberg::PluginHash;
require Zoidberg::StringParser;

use Data::Dumper;
use Zoidberg::DispatchTable _prefix => '_', 'stack';
use Zoidberg::Utils 
	qw/:error :output :fs :fs_engine read_data_file merge_hash is_exec_in_path/;
#use Zoidberg::IPC;

our @ISA = qw/Zoidberg::Contractor Zoidberg::Shell/;

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
	$self->{shell} = $self; # for Contractor

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
	$self->{events}{postcmd} = sub {
		my $pwd = Cwd::cwd();
		@ENV{qw/OLDPWD PWD/} = ($ENV{PWD}, $pwd)
			unless $pwd eq $ENV{PWD} ;
	};

	## contexts
	my %contexts;
	tie %contexts, 'Zoidberg::DispatchTable', $self;
	$self->{contexts} = \%contexts;

#    $self->{ipc} = Zoidberg::IPC->new($self);
#    $self->{ipc}->init;

	## parser 
	my $coll = read_data_file('grammar');
	$self->{stringparser} = Zoidberg::StringParser->new($coll->{_base_gram}, $coll);

	## setup eval namespace
	$self->{eval} = Zoidberg::Eval->_new($self);
	
	## initialize contractor
	$self->shell_init;

	## plugins
	my %objects;
	tie %objects, 'Zoidberg::PluginHash', $self;
	$self->{objects} = \%objects;

	## path cache
	my $file_cache = "$cache_dir/zoid_path_cache" ;
	if (-s $file_cache) { f_read_cache($file_cache) }
	else {
		message 'Initializing PATH cache.';
		f_index_path();
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
	
	while ($self->{_continue}) {
		$self->broadcast('precmd');

		my $cmd = eval { $self->Buffer->get_string };
		last unless $self->{_continue}; # buffer can call exit
		if ($@) {
			complain "\nBuffer died. (You can interrupt zoid NOW)\n$@";
			local $SIG{INT} = 'DEFAULT';
			sleep 1; # infinite loop protection
		}
		else { 
			$self->broadcast('cmd', $cmd);
			print STDERR $cmd if $self->{settings}{verbose}; # posix spec

			$self->shell_string($cmd);
		}
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

sub list_clothes { # includes $self->{vars}
	my $self = shift;
	my @return = map {'{'.$_.'}'} sort @{$self->{settings}{clothes}{keys}};
	push @return, sort @{$self->{settings}{clothes}{subs}};
	return [@return];
}

sub list_vars { return [map {'{'.$_.'}'} sort keys %{$_[0]->{vars}}]; }

# ############ #
# Parser stuff #
# ############ #

sub shell_string {
	my ($self, $meta, @list) = @_;
	unless (ref($meta) eq 'HASH') {
			unshift @list, $meta;
			undef $meta;
	}
	local $ENV{ZOIDREF} = $self;
	@list = $$self{stringparser}->split('script_gram', @list);
	my $e = $$self{stringparser}->error;
	return complain $e if $e;
	# TODO pull code here
	debug 'block list: ', \@list;
	return $self->shell_list($meta, @list); # calling contractor
}

sub parse_block  { 
	# call as late as possible before execution
	# bit is "broken bit" (also known as "Intel bit")
	my ($self, $block, $queue, $bit) = @_;
	my ($meta, @words) = ({broken => $bit});

	# decipher block
	my $t = ref $block;
	if (!$t or $t eq 'SCALAR') {
		$$meta{string} = $t ? $$block : $block;
		@words = grep {length $_} $self->{stringparser}->split('word_gram', $$meta{string});
	}
	elsif ($t eq 'ARRAY') {
		$meta = { %$meta, %{shift @$block} }
			if ref($$block[0]) eq 'HASH';
		@words = @$block;
	}
	else { bug "parse tree contains $t reference" }

	return undef unless grep {length $_} @words;

	($meta, @words) = $self->_filter($meta, @words);
	return [$meta, @words] if $$meta{context};

	# check builtin contexts
	unless ($$meta{context} || $$self{settings}{_no_hardcoded_context}) {
		debug 'trying builtin contexts';
		my $perl_regexp = join '|', @{$self->{settings}{perl_keywords}};
		if (
			(@words == 1) && $words[0] =~ s/^\s*(\w*){(.*)}(\w*)\s*$/$2/s
			or $$meta{broken} && $words[0] =~ s/^\s*(\w*){(.*)$/$2/s
		) {
			if (! $1 or uc($1) eq 'ZOID') {
				@$meta{qw/context dezoidify _no_words opts/} = ('PERL', 1, 1, $3 || '');
			}
			elsif (grep {$_ eq $1} qw/s tr y/) {
				@$meta{qw/context _no_words/} = ('PERL', 1);
				$words[0] = $1.'{'.$2.'}'.$3 ;
			}
			else {
				@$meta{qw/context opts/} = (uc($1), $3 || '');
				if (
					$$meta{context} eq 'SH' or $$meta{context} eq 'CMD'
					or exists $self->{contexts}{$$meta{context}}{word_list}
				) { # split words agan
					@words = $self->_split_words($words[0], $$meta{broken});
				}
			}
		}
		elsif ($words[0] =~ /^\s*(->|[\$\@\%\&\*\xA3]\S|\w+[\(\{]|($perl_regexp)\b)/s) {
			@$meta{qw/context dezoidify/} = ('PERL', 1);
			($meta, @words) = @{ $self->_no_words([$meta, @words]) };
		} 
	}

	# check custom contexts
	unless ($$meta{context}) {
		debug 'trying custom contexts';
		for (keys %{$self->{contexts}}) {
			next unless exists $self->{contexts}{$_}{word_list};
			my $r = $self->{contexts}{$_}{word_list}->([$meta, @words]);
			unless ($r) { next }
			elsif (ref $r) { ($meta , @words) = @$r }
			else { $$meta{context} = length($r) > 1 ? $r : $_ }
			last if $$meta{context};
		}
	}
	
	# check more builtin contexts
	unless ($$meta{context} || $$self{settings}{_no_hardcoded_context}) {
		debug 'trying more builtin contexts';
#		no strict 'refs';
		if (
#			defined *{"Zoidberg::Eval::$words[0]"}{CODE} or
			exists $self->{commands}{$words[0]}
		) { $$meta{context} = 'CMD' }
		elsif (
			($words[0] =~ m!/! and -x $words[0] and ! -d $words[0])
			or is_exec_in_path($words[0])
		) { $$meta{context} = 'SH' }
		$$meta{_is_checked}++ if $$meta{context};

		# hardcoded default context
		unless ($$meta{context} || $$meta{broken}) {
			debug 'going for the default context';
			$$meta{context} = 'SH';
		} # just leave blank for broken syntax
	}

	($meta, @words) = @{ $self->_do_words([$meta, @words]) }
		if @words && ! @$meta{qw/broken _no_words/} ;
	return [$meta, @words];
}

sub _filter {
	my ($self, $meta, @words) = @_;

	# parse environment
	unless ( $$self{settings}{_no_env} ) {
		while ($words[0] =~ /^([A-Z][A-Z_\-\d]*)=(.*)/) {
			$$meta{start} ||= [];
			my (undef, @w) = @{ $self->_do_words([{_no_topic => 1}, $2]) };
			$$meta{env}{$1} = join ':', @w;
			push @{$$meta{start}}, shift @words;
		}
	}

	# parse redirections
	unless (
		$$self{settings}{_no_redirection}
		|| ($#words < 2)
		|| $words[-2] !~ /^(\d?)(>>|>|<)$/
	) {
		# FIXME what about escapes ? (see posix spec)
		# FIXME more types of redirection
		# FIXME are it always _2_ words ?
		$$meta{end} = [ splice @words, -2 ];
		my $num = $1 || ( ($2 eq '<') ? 0 : 1 );
		my (undef, @w) = @{ $self->_do_words([{_no_topic => 1}, $$meta{end}[-1]]) };
		my $file = (@w == 1) ? $w[0] : $$meta{end}[-1];
		$$meta{fd}{$num} = [ $file, $2 ];
	}

	# check custom filters
	for (keys %{$self->{contexts}}) {
		next unless exists $self->{contexts}{$_}{filter};
		my $r = $self->{contexts}{$_}{filter}->([$meta, @words]);
		($meta, @words) = @$r if $r; # skip on undef
	}

	@words = $self->_do_aliases(@words) if @words && ! $$meta{broken};

	return ($meta, @words);
}

sub _do_aliases {
	my ($self, $key, @rest) = @_;
	if (exists $self->{aliases}{$key}) {
		my $string = $self->{aliases}{$key}; # TODO Should we support other data types ?
		@rest = $self->_do_aliases(@rest)
			if $string =~ /\s$/; # recurs for 2nd word - see posix spec
		unshift @rest, grep {defined $_} $self->{stringparser}->split('word_gram', $string);
		return $self->_do_aliases(@rest) unless $rest[0] eq $key; # recurs
		return @rest;
	}
	else { return ($key, @rest) }
}

sub _no_words { # reconstruct original string
	my ($self, $block) = @_;
	my $string = $$block[0]{string};
	bug 'need meta field "string" to do _no_words' unless $string;
	if (exists $$block[0]{end}) {
		$string =~ s/\s*\Q$_\E\s*$//
			for reverse @{$$block[0]{end}};
	}
	if (exists $$block[0]{start}) {
		$string =~ s/^\s*\Q$_\E\s*//
			for @{$$block[0]{start}};
	}
	$$block[0]{_no_words}++;
	$block = [ $$block[0], $string ];
	return $block;
}

sub _do_words { # expand words etc.
	my ($self, $block) = @_;
#	@$block = $_->(@$block) for _stack($$self{contexts}, 'words_expansion');
	@$block = $self->$_(@$block) for qw/_expand_param _expand_path/;
	$self->{topic} = $$block[-1] unless $$block[0]{_no_topic};
	return $block;
}

sub _expand_param { # FIXME @_ implementation
	my ($self, $meta, @words) = @_;
	for (@words) {
		next if /^'.*'$/;
		s{ (?<!\\) \$ (?: \{ (.*?) \} | (\w+) ) (?: \[(\d+)\] )? }{
			my ($w, $i) = ($1 || $2, $3);
			error "no advanced expansion for \$\{$w\}" if $w =~ /\W/;
			$w = 	($w eq '_') ? $$self{topic} :
				(exists $$meta{env}{$w}) ? $$meta{env}{$w}  : $ENV{$w};
			$i ? (split /:/, $w)[$i] : $w;
		}exg;
	}
	@words = map {
		if (m/^ \@ (?: \{ (.*?) \} | (\w+) ) $/x) {
			my $w = $1 || $2;
			error "no advanced expansion for \@\{$w\}" if $w =~ /\W/;
			$w = (exists $$meta{env}{$w}) ? $$meta{env}{$w}  : $ENV{$w};
			split /:/, $w;
		}
		else { $_ }
	} @words;
	return ($meta, @words);
}

sub _command_subst {
	my ($self, $meta, @words) = @_;
	for (@words) {
		next if /^'.*'$/;
		# FIXME FIXME FIXME this should be done by stringparser
		# s{ (?<!\\) (?: \$\( (.*?) \) | \` (.*?) (?<!\\) \` }{
		# if wantarray @parts else join ':', @parts
	}
}

# See File::Glob for explanation of behaviour
our $_GLOB_OPTS = File::Glob::GLOB_TILDE() | File::Glob::GLOB_BRACE() | File::Glob::GLOB_QUOTE() ;
our $_NC_GLOB_OPTS = $_GLOB_OPTS | File::Glob::GLOB_NOCHECK();

sub _expand_path { # path expansion
	my ($self, $meta, @files) = @_;
	unless ($self->{shell}{settings}{noglob}) {
		@files = map { /^['"](.*)['"]$/ ? $1 : File::Glob::bsd_glob($_, 
			$$self{settings}{allow_null_glob_expansion} ? $_GLOB_OPTS : $_NC_GLOB_OPTS
		) } @files ;
	}
	else {  @files = map { /^['"](.*)['"]$/ ? $1 : $_ } @files  } # quote removal
	return ($meta, @files);
}

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

sub broadcast { # eval to be sure we return
	my ($self, $event) = (shift(), shift());
	return unless exists $self->{events}{$event};
	debug "Broadcasting event: $event";
	for my $sub (_stack($self->{events}, $event)) {
		eval { $sub->($event, @_) };
		complain("$sub died on event $event ($@)") if $@;
	}
}

sub call {
	my ($self, $event) = (shift(), shift());
	return unless exists $self->{events}{$event};
	debug "Calling event: $event";
	$self->{events}{$event}->($event, @_);
}

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
	$self->broadcast('exit');
	if ($self->{round_up}) {
		foreach my $n (keys %{$self->{objects}}) {
			#print "debug roud up: ".ref( $self->{objects}{$n})."\n";
			if (ref($self->{objects}{$n}) && $self->{objects}{$n}->isa('Zoidberg::Fish')) {
				$self->{objects}{$n}->round_up;
			}
		}
		Zoidberg::Contractor::round_up($self);

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

Probably you just want the program F<zoid> which is the system command
to start the Zoidberg shell. If you really want to initialize the module directly 
you should check the code of F<zoid> for an elaborate example.

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

=item C<exit()>

Called by plugins to exit zoidberg -- this ends a interactive C<main_loop()> loop

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

package Zoidberg;

our $VERSION = '0.52';
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
require Zoidberg::Contractor;
require Zoidberg::Shell;
require Zoidberg::PluginHash;
require Zoidberg::StringParser;

use Zoidberg::DispatchTable _prefix => '_', 'stack';
use Zoidberg::Utils
	qw/:error :output :fs :fs_engine read_data_file merge_hash/;
#use Zoidberg::IPC;

our @ISA = qw/Zoidberg::Contractor Zoidberg::Shell/;

our %OBJECTS; # used to store refs to ALL Zoidberg objects in a process
our $CURRENT; # current Zoidberg object

our $_base_dir; # relative path for some settings
our %_settings; ##Insert defaults here##

sub new {
	my ($class, $self) = @_;
	$self ||= {};
	$$self{$_} ||= {} for qw/settings commands aliases events objects vars/;
	$$self{no_words} ||= ['PERL']; # parser HACK might be fixed some day
	$$self{round_up}++;
	$$self{topic} ||= '';

	bless($self, $class);

	$OBJECTS{"$self"} = $self;
	$CURRENT = $self unless ref( $CURRENT ) eq $class; # could be autovivicated
	$self->{shell} = $self; # for Contractor

	## settings
	$self->{settings}{$_} ||= $_settings{$_} for keys %_settings;
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
		( %{$$self{commands}} )
	};
	$$self{commands} = \%commands;

	## events
	my %events;
	tie %events, 'Zoidberg::DispatchTable', $self, $$self{events};
	$$self{events} = \%events;
	$$self{events}{envupdate} = sub {
		my $pwd = Cwd::cwd();
		return if $pwd eq $ENV{PWD};
		@ENV{qw/OLDPWD PWD/} = ($ENV{PWD}, $pwd);
		$self->broadcast('newpwd');
	};
	$$self{events}{readline} = "->_stdin('zoid-$VERSION\$ ')";
	$$self{events}{readmore} = "->_stdin('> ')";

	## contexts
	my %contexts;
	tie %contexts, 'Zoidberg::DispatchTable', $self, $$self{contexts};
	$$self{contexts} = \%contexts;

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
	f_read_cache($file_cache) if -s $file_cache;
	$self->{events}{prompt} = \&f_wipe_cache;

	## let's load the rcfiles
	$self->source(grep {-f $_} @{$$self{settings}{rcfiles}});

	return $self;
}

sub import { bug "You should use Zoidberg::Shell to import from" if @_ > 1 }

# hooks overloading Contracter
*pre_job = \&parse_block;
*post_job = \&broadcast;

# ############ #
# Main routine #
# ############ #

sub main_loop {
	my $self = shift;

	$$self{_continue} = 1;
	while ($$self{_continue}) {
		$self->reap_jobs();
		$self->broadcast('prompt');
		my $cmd = eval { $$self{events}{readline}->() };
		if ($@) {
			complain "\nInput routine died. (You can interrupt zoid NOW)\n$@";
			local $SIG{INT} = 'DEFAULT';
			sleep 1; # infinite loop protection
		}
		else {
			$self->reap_jobs();
			$self->exit() unless defined $cmd || $$self{settings}{ignoreeof};
			last unless $$self{_continue};
			$self->broadcast('cmd', $cmd);
			print STDERR $cmd if $$self{settings}{verbose}; # posix spec
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

sub list_clothes {
	my $self = shift;
	my @return = map {'{'.$_.'}'} sort @{$self->{settings}{clothes}{keys}};
	push @return, sort @{$self->{settings}{clothes}{subs}};
	return [@return];
}

sub list_vars { return [map {'{'.$_.'}'} sort keys %{$_[0]->{vars}}] }

# ############ #
# Parser stuff #
# ############ #

sub shell_string {
	my ($self, $meta, @list) = @_;
	unless (ref($meta) eq 'HASH') {
			unshift @list, $meta;
			undef $meta;
	}
	local $CURRENT = $self;
	@list = $$self{stringparser}->split('script_gram', @list);
	my $e = $$self{stringparser}->error;
	return complain $e if $e;
	# TODO pull code here
	debug 'block list: ', \@list;
	$$self{fg_job} ||= $self;
	return $$self{fg_job}->shell_list($meta, @list); # calling a contractor
}

sub parse_block  { 
	# call as late as possible before execution
	# bit is "pretend bit" (also known as "Intel bit")
	# $queue is unshift only, no shift - else you can fuck up logic list
	my ($self, $block, $queue, $bit) = @_; # queu isn't no more - extra meta instead me thinks
	my ($meta, @words) = ({pretend => $bit});

	# decipher block
	my $t = ref $block;
	if (!$t or $t eq 'SCALAR') { $$meta{string} = $t ? $$block : $block }
	elsif ($t eq 'ARRAY') {
		$meta = { %$meta, %{shift @$block} } if ref($$block[0]) eq 'HASH';
		@words = @$block;
	}
	else { bug "parse tree contains $t reference" }

	# check aliase and other meta stuff
	my @blocks = $self->parse_macros($meta, @words);
	if (@blocks > 1) { # alias contained pipe or logic operator
		bug 'No queue argument given' unless ref $queue;
		($meta, @words) = @{ shift(@blocks) };
		unshift @$queue, @blocks;
	}
	elsif (@blocks) { ($meta, @words) = @{ shift(@blocks) } }
	else { return undef }

	# check custom filters
	for my $sub (_stack($$self{contexts}, 'filter')) {
		my $r = $sub->([$meta, @words]);
		($meta, @words) = @$r if $r; # skip on undef
	}

	# check builtin contexts
	unless ($$meta{context} or $$self{settings}{_no_hardcoded_context}) {
		debug 'trying builtin contexts';
		my $perl_regexp = join '|', @{$self->{settings}{perl_keywords}};
		if (
			$$meta{string} =~ s/^\s*(\w*){(.*)}(\w*)\s*$/$2/s
			or $$meta{pretend} and $$meta{string} =~ s/^\s*(\w*){(.*)$/$2/s
		) { # all kinds of blocks with { ... }
			unless (length $1) { @$meta{qw/context opts/} = ('PERL', $3 || '') }
			elsif (grep {$_ eq $1} qw/s m tr y/) {
				$$meta{string} = $1.'{'.$$meta{string}.'}'.$3; # always one exception
				@$meta{qw/context opts/} = ('PERL', ($1 eq 'm') ? 'g' : 'p')
			}
			else {
				@$meta{qw/context opts/} = (uc($1), $3 || '');
				@words = grep {length $_} $self->{stringparser}->split('word_gram', $$meta{string});
			}
		}
		elsif ($$meta{string} =~ s/^\s*(\w+):\s+//) { # little bit o psh2 compat
			$$meta{context} = uc $1;
			shift @words;
		}
		elsif ($words[0] =~ /^\s*(->|[\$\@\%\&\*\xA3]\S|\w+::|\w+[\(\{]|($perl_regexp)\b)/s) {
			$$meta{context} = 'PERL';
		}
	}

	return [$meta, @words] if $$meta{pretend} and @words == 1;

	# check custom contexts
	unless ($$meta{context}) {
		debug 'trying custom contexts';
		for my $pair (_stack($$self{contexts}, 'word_list', 'TAGS')) {
			my $r = $$pair[0]->([$meta, @words]);
			unless ($r) { next }
			elsif (ref $r) { ($meta , @words) = @$r }
			else { $$meta{context} = length($r) > 1 ? $r : $$pair[1] }
			last if $$meta{context};
		}
	}

	# check default builtin contexts
	unless ($$meta{context} || $$self{settings}{_no_hardcoded_context}) {
		debug 'using default contexts';
		$$meta{context} = exists( $$self{commands}{$words[0]} ) ? 'CMD' : 'SH' ;
	}

	if (exists $$self{contexts}{$$meta{context}}{parser}) { # custom parser
		($meta, @words) = @{ $$self{contexts}{$$meta{context}}{parser}->([$meta, @words]) };
	}
	elsif (grep {$$meta{context} eq $_} @{$$self{no_words}}) { # no words
		if ($$meta{pretend}) { @words = grep {length $_} $self->{stringparser}->split('word_gram', $$meta{string}) }
		else { @words = ($$meta{string}) }
	}
	elsif (@words and ! $$meta{pretend}) { # expand and set topic
		($meta, @words) = @{ $self->parse_words([$meta, @words]) }; # uses old topic
		$$self{topic} =
			exists($$meta{fd}{0}) ? $$meta{fd}{0}[0] :
			(@words > 1 and $words[-1] !~ /^-/) ? $words[-1] : $$self{topic};
		$$meta{fork_job} = 1 if $$meta{context} eq 'SH'; # custom contexts do this in parser sub
	}
	return [$meta, @words];
}

sub parse_macros {
	my ($self, $meta, @words) = @_;

	unless (@words) {
		@words = grep {length $_} $self->{stringparser}->split('word_gram', $$meta{string})
	}
	else { delete $$meta{string} } # just to make sure

	# parse environment
	unless ( $$self{settings}{_no_env} ) {
		while ($words[0] =~ /^(\w[\w\-]*)=(.*)/) {
			push @{$$meta{start}}, shift @words;
			$$meta{start} ||= [];
			my (undef, @w) = @{ $self->parse_words([{}, $2]) };
			$$meta{env}{$1} = join ':', @w;
		}
		if (! @words and $$meta{env}) { # special case
			@words = ('export', map $_.'='.$$meta{env}{$_}, keys %{$$meta{env}});
			$$meta{string} = '';
			delete $$meta{start};
			delete $$meta{env}; # duplicate would make var local
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
		my (undef, @w) = @{ $self->parse_words([{}, $$meta{end}[-1]], 'NO_TOPIC') };
		my $file = (@w == 1) ? $w[0] : $$meta{end}[-1];
		$$meta{fd}{$num} = [ $file, $2 ];
	}

	@words = $self->_do_aliases(@words) if @words && ! $$meta{pretend};

	if ($$meta{string}) {
		if (exists $$meta{end}) {
			$$meta{string} =~ s/\s*\Q$_\E\s*$//
				for reverse @{$$meta{end}};
		}
		if (exists $$meta{start}) {
			$$meta{string} =~ s/^\s*\Q$_\E\s*//
				for @{$$meta{start}};
		}
	}
	else { $$meta{string} = join ' ', @words }

	$$meta{env}{ZOIDCMD} ||= $$meta{string}; # unix haters guide pdf page 60
	return [$meta, @words];
}

sub _do_aliases { # only a sub to be able to recurs
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

sub parse_words { # expand words etc.
	my ($self, $block) = @_;
#	@$block = $_->(@$block) for _stack($$self{contexts}, 'words_expansion');
	@$block = $self->$_(@$block) for qw/_expand_param _expand_path/;
	return $block;
}

sub _expand_param { # FIXME @_ implementation
	my ($self, $meta, @words) = @_;
	for (@words) {
		next if /^'.*'$/;
		s{ (?<!\\) \$ (?: \{ (.*?) \} | (\w+) ) (?: \[(-?\d+)\] )? }{
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
	return $meta, map { /^['"](.*)['"]$/ ? $1 : $_ } @files if $$self{settings}{noglob};
	my $opts = $$self{settings}{allow_null_glob_expansion} ? $_GLOB_OPTS : $_NC_GLOB_OPTS;
	return $meta, map {
		if (/^['"](.*)['"]$/) { $1 }
		else {
			my @r = File::Glob::bsd_glob($_, $opts);
			($_ !~ /^-/) ? (grep {$_ !~ /^-/} @r) : (@r);
			# protect against implict switches as file names
		}
	} @files ;
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

sub _stdin { # stub STDIN input
	my (undef, $prompt) = @_;
	local $/ = "\n";
	print $prompt;
	return <STDIN>;
};

# ########### #
# Event logic #
# ########### #

sub broadcast { # eval to be sure we return
	my ($self, $event) = (shift(), shift());
	$event ||= 'envupdate'; # generic heartbeat
	return unless exists $self->{events}{$event};
	debug "Broadcasting event: $event";
	for my $sub (_stack($$self{events}, $event)) {
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
		debug "No such method or object: '$call', trying to shell() it";
		@_ = ([$call, @_]); # force words parsing
		goto \&Zoidberg::Shell::shell;
	}
}

# ############# #
# Exit routines #
# ############# #

sub exit {
	my $self = shift;
	if (@{$$self{jobs}} and ! $$self{_warned_bout_jobs}) {
		complain "There are unfinished jobs";
		$$self{_warned_bout_jobs}++;
	}
	else {
		message join ' ', @_;
		$self->{_continue} = 0;
	}
	# FIXME this should force ReadLine to quit
}

sub round_up {
	my $self = shift;
	$self->broadcast('exit');
	if ($self->{round_up}) {
		tied( %{$$self{objects}} )->round_up(); # round up loaded plugins
		Zoidberg::Contractor::round_up($self);

		f_save_cache($self->{settings}{cache_dir}.'/zoid_path_cache');

		undef $self->{round_up};
	}
	return $$self{error} unless $$self{settings}{interactive};
}

sub DESTROY {
	my $self = shift;
	if ($$self{round_up}) {
		warn "Zoidberg was not properly cleaned up.\n";
		$self->round_up;
	}
	delete $OBJECTS{"$self"};
}

1;

__END__

=head1 NAME

Zoidberg - a modular perl shell

=head1 SYNOPSIS

You should use the B<zoid> system command to start the Zoidberg shell.
If you want to initialize the module directly see the code of B<zoid> for an elaborate example.

=head1 DESCRIPTION

I<This page contains devel documentation, if you're looking for user documentation start with the zoid(1) man page.>

This class provides the main object of the Zoidberg shell, all other objects are nested 
below attributes of this object.
Also it contains some parser code along with methods to manage the events and plugin framework.

=head1 ATTRIBUTES

FIXME - see also zoiddevel(1)

=head1 METHODS

FIXME list all methods

Some methods:

=over 4

=item C<new(%attr)>

Initialize secondary objects and sets config. C<%attr> contains attributes to be used
and is used to set runtime settings.

=item C<main_loop()>

Spans interactive shell reading from a secondary ReadLine object or from STDIN.
To quit this loop the routine C<exit()> of this package should be called.

=item C<list_objects()>

List secondary objects. These do not need to be loaded allready, 
the list is based on the config files.

=item C<exit()>

Called by plugins to exit zoidberg -- this ends a interactive C<main_loop()> loop.
This does not clean up or destroy any objects, this means the C<main_loop()> can be 
called again to restart it.

=item C<round_up()>

This method should be called to clean up the shell objects.
A C<round_up()> method will be called recursively for all secondairy objects.

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

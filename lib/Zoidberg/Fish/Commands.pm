package Zoidberg::Fish::Commands;

our $VERSION = '0.3b';

use strict;
use Cwd;
use Env qw/@CDPATH/;
use Data::Dumper;
use Zoidberg::Error;
use base 'Zoidberg::Fish';
#require Benchmark;
use Zoidberg::FileRoutines qw/abs_path/;

# FIXME what to do with commands that use block input ?
#  currently hacked with statements like join(' ', @_)

sub init { 
	$_[0]->{dir_hist} = [$ENV{PWD}];
	$_[0]->{_dir_hist_i} = 0;
}

sub exec { # not completely stable I'm afraid
	my $self = shift;
	$self->{parent}->{round_up} = 0;
	$self->{parent}->parse(join(" ", @_));
	# the process should not make it to this line
	$self->{parent}->{round_up} = 1;
	$self->{parent}->exit;
}

sub eval {
	my $self = shift;
	$self->parent->do( join( ' ', @_) );
	error $self->{parent}{exec_error}
		if $self->{parent}{exec_error};
}

sub source { 
	my $self = shift;
	my $file = shift || $self->parent->{_};
	$file = abs_path($file);
	error "source: no such file: $file" unless -f $file;
	$self->parent->{_} = $file;
	do $file;
	die if $@;
}

sub setenv {
	my $self = shift;
	my $string = join(" ", @_);
	if ($string =~ m/^\s*(\w*)\s*=\s*['"]?(.*?)['"]?\s*$/) { $ENV{$1} = $2; }
	else { error 'argument syntax error' }
}

sub set {
	my $self = shift;
	# FIXME use some getopt
	# be aware '-' is set '+' is unset (!!??)
	unless (@_) { todo 'I should printout all shell vars' }

	my ($sw, $opt, $val);
	if ($_[0] =~ m/^([+-])(\w+)/) {
		shift;
		$sw = $1;
		my %args = ( # quoted is yet unsupported
			#a => 'allexport',	b => 'notify',
			#C => 'noclobber',	e => 'errexit',
			f => 'noglob',		#m => 'monitor',	
			#n => 'noexec',		u => 'nounset',
			v => 'verbose',		#x => 'xtrace',
		);
		# other posix options: ignoreeof, nolog & vi
		if ($2 eq 'o') { $opt = shift }
		elsif ($args{$2}) { $opt = $args{$2} }
		else { error "Switch $sw not (yet?) supported." }
	}
	else { 
		$opt = shift;
		$sw = '-';
		if ($opt =~ m/^(\w+)=(.*)$/) { ($opt, $val) = ($1, $2) }
		elsif ($opt =~ m/^(.*)([+-]{2})$/) { 
			$opt = $1;
			$sw = '+' if $2 eq '--'; # sh has evil logic
		}
	}
	
	$val = shift unless defined $val;
	error "Setting $opt is a data structure" if ref $self->{settings}{$opt};
	
	if ($sw eq '+') { delete $self->{settings}{$opt} }
	else { $self->{settings}{$opt} = $val || 1 }
}

sub alias {
	my $self = shift;
	unless (@_) {
		for (keys %{$self->{parent}{aliases}}) { 
			$self->{parent}->print( q/alias /.$_.q/='/.$self->{parent}{aliases}{$_}.q/'/);
		}
		return;
	}
	for (@_) {
		error 'alias: wrong argument format' unless /^(\w+)=['"]?(.*?)['"]?$/;
		$self->{parent}{aliases}{$1} = $2;
	}
}

sub read { todo }

sub wait { todo }

sub fc { todo }

sub getopts { todo }

sub command { todo }

sub newgrp { todo }

sub umask { todo }

sub unalias { todo }

sub false { error {silent => 1} }

sub true { 1 }

sub cd {
	my $self = shift;

	# TODO [-L|-P] see man 1 bash
	# FIXME remove '->' and '<-' and use '-b', '--back', '-f', '--forward' instead
	# the /[<>-]+/ gives parsing issues with shell syntax
	my ($dir, $browse_hack);
	if ($_[0] =~ /^-|<-/) {
		$dir = $self->__get_dir_hist(@_);
		# TODO seperated error for wrongly formatted input
		error q{History index out of range} unless defined $dir;
		$browse_hack++;
	}
	else { $dir = shift }

	# due to things like autofs we must try every possibility
	# instead of checking '-d'

	my $done;
	if ($dir) {
		$dir =~ s{(?<!^)/$}{}; # cut trailing slash

		my @dirs = ($dir);
		push @dirs, map {$_.'/'.$dir} @CDPATH unless $dir =~ m{^/};

		for (@dirs) {
			$dir = abs_path($_);
			# print "Denug: Trying dir --$dir--\n";
			last if $done = chdir $dir;
		}
	}
	else { $done = chdir($self->parent->{_}) || chdir() }

	if ($done) {
		$ENV{OLDPWD} = $ENV{PWD};
		$ENV{PWD} = getcwd;
		$self->__add_dir_hist unless $browse_hack;
	}
	else { 
		error $dir.': Not a directory' unless -d $dir;
		error "Could not change to dir: $dir";
	}
}

##################
#### Dir Hist ####
##################

sub __add_dir_hist {
	my $self = shift;
	my $dir = shift || $ENV{PWD};

	return if $dir eq $self->{dir_hist}[0];

	unshift @{$self->{dir_hist}}, $dir;
	$self->{_dir_hist_i} = 0;

	my $max = $self->{config}{max_dir_hist} || 5;
	pop @{$self->{dir_hist}} if $#{$self->{dir_hist}} > $max ;
}

sub __get_dir_hist {
	my $self = shift;

	my ($sign, $num);
	if (scalar(@_) > 1) { ($sign, $num) = @_ }
	elsif (@_) { 
		$_[0] =~ /^\s*(-|->|<-)(\d*)\s*$/ || return undef;
		($sign, $num) = ($1, $2 || 1);
	}
	else { $sign = '-' }

	if ($sign eq '-') { return $ENV{OLDPWD} }
	elsif ($sign eq '->') { $self->{_dir_hist_i} -= $num }
	elsif ($sign eq '<-') { $self->{_dir_hist_i} += $num }
	else { return undef }

	return undef if $num < 0 || $num > $#{$self->{dir_hist}};
	return $self->{dir_hist}[$num];
}

##################

sub pwd {
	my $self = shift;
	$self->parent->print($ENV{PWD});
}

sub _delete_object { # FIXME some kind of 'force' option to delte config, so autoload won't happen
	my $self = shift;
	if (my $zoidname = shift) {
        	unless (ref($self->{parent}{objects}{$zoidname})) {
			error "No such object: $zoidname";
		}
		$self->unregister_all_events($zoidname);
		if ($self->{parent}{objects}{$zoidname}->isa('Zoidberg::Fish')) {
			$self->{parent}{objects}{$zoidname}->round_up;
		}
		delete $self->{parent}{objects}{$zoidname};
	}
	else { error 'Usage: $command $object_name' }
}

sub _load_object {
	my $self = shift;
	if (my $name = shift) {
		if (my $class = shift) { $self->{parent}->init_object($name, $class, @_) }
		return 0;
	}
	error 'Usage: $command $object_name $class_name';
}

sub _hide {
	my $self = shift;
	my $ding = shift || $self->{parent}->{_};
	if ($ding =~ m/^\{(\w*)\}$/) {
		@{$self->{settings}{clothes}{keys}} = grep {$_ ne $1} @{$self->{settings}{clothes}{keys}};
	}
	elsif ($ding =~ m/^\w*$/) {
		@{$self->{settings}{clothes}{subs}} = grep {$_ ne $ding} @{$self->{settings}{clothes}{subs}};
	}
}

sub _unhide {
	my $self = shift;
	my $ding = shift || $self->{parent}->{_};
	$self->{parent}->{_} = '->'.$ding;
	if ($ding =~ m/^\{(\w*)\}$/) { push @{$self->{settings}{clothes}{keys}}, $1; }
	elsif (($ding =~ m/^\w*$/)&& $self->parent->can($ding) ) {
		push @{$self->{settings}{clothes}{subs}}, $ding;
	}
	else { error 'Dunno such a thing' }
}

sub echo {
	my $self = shift;
	my $string = join(" ", @_) || $self->{parent}->{_};
	$self->{parent}->{_} = $string;
	$self->{parent}->print($string);
}

sub quit {
	my $self = shift;
	if (@_) { $self->{parent}->print(join(" ", @_)); }
	$self->{parent}->History->del; # leave no trace # FIXME - ergggg vunzig
	$self->{parent}->exit;
}

=begin comment

sub _time {
    my $self = shift;
    if (@_) {
        my $kontwange = join(" ",@_);
        $self->print(Benchmark::timestr(Benchmark::timeit(1,sub{$self->parent->parse($kontwange)}),'nop'));
    }
    else { error 'usage: $command something' }
}

=end comment

=cut

1;

__END__

=head1 NAME

Zoidberg::Fish::Commands - Zoidberg plugin for internal commands

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This object handles internal commands
for the Zoidberg shell, it is a core object.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 parse($command, @options)

  Execute command $command

=head2 c_*

  Methods bound to specific commands

=head2 list()

  List commands

=head2 help()

  Output helpfull text


=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>, L<Zoidberg>, L<Zoidberg::Fish>, L<http://zoidberg.sourceforge.net>

=cut

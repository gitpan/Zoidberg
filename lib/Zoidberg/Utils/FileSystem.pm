package Zoidberg::Utils::FileSystem;

our $VERSION = '0.53';

use strict;
#use File::Spec;
use Carp;
use Env qw/@PATH/;
use File::Spec; # TODO make more use of this lib
use Zoidberg::Utils::Output qw/debug message/;
use Exporter::Tidy 
	default => [qw/abs_path list_path list_dir unique_file/],
	engine  => [qw/index_path wipe_cache read_cache save_cache/];

our $cache = { VERSION => $VERSION };
our $cache_atime = 300; # 5x60 -- 5 minutes
our $dump_file = '';

our $DEVNULL = File::Spec->devnull();

our $_storable = eval 'use Storable qw(lock_store lock_retrieve); 1';
warn "No Storable available, dir listing cache disabled\n" unless $_storable;

## Basic file routines ##

sub abs_path {
	# return absolute path
	# argument: string optional: reference
	# FIXME use File::Spec in this sub
	my $string = shift || return $ENV{PWD};
	my $refer = $_[0] ? abs_path(shift @_) : $ENV{PWD}; # possibly recurs
	$refer =~ s/\/$//;
	$string =~ s{/+}{/}; # ever tried using $::main::main::main::something ?
	unless ($string =~ m{^/}) {
		if ( $string =~ /^~([^\/]*)/ ) {
			if ($1) {
				my @info = getpwnam($1); 
				# @info = ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell).
				$string =~ s{^~$1/?}{$info[7]/};
			}
			else { $string =~ s{^~/?}{$ENV{HOME}/}; }
		}
		elsif ( $string =~ s{^\.(\.+)(/|$)}{}) { 
			my $l = length($1);
			$refer =~ s{(/[^/]*){0,$l}$}{};
			$string = $refer.'/'.$string;
		}
		else {
			$string =~ s{^\.(/|$)}{};
			$string = $refer.'/'.$string;
		}
	}
	$string =~ s/\\//g;
	return $string;
}

sub list_dir {
	my $dir = shift || $ENV{PWD};
	$dir =~ s#/$## unless $dir eq '/';
	$dir = abs_path($dir) unless $$cache{dirs}{$dir};
	
	my $mtime = (stat($dir))[9];
	return @{read_dir($dir, @_)->{items}}
		unless exists $$cache{dirs}{$dir}
		and $mtime == $$cache{dirs}{$dir}{mtime};

	$$cache{dirs}{$dir}{cache_atime} = time;
	return @{$$cache{dirs}{$dir}{items}};
}

sub read_dir {
	my $dir = shift;
	debug "(re-) scanning directory: $dir";
	if (-e $dir) {
		my $no_wipe = shift || $cache->{dirs}{$dir}{no_wipe};
		$$cache{dirs}{$dir} = {
			path => $dir,
			mtime => (stat($dir))[9],
			cache_atime => time,
			no_wipe => $no_wipe,
		};
		opendir DIR, $dir or croak "could not open dir: $dir";
		$$cache{dirs}{$dir}{items} = [ grep {$_ !~ /^\.{1,2}$/} readdir DIR ];
		closedir DIR;
	}
	else { croak "no such dir: $dir" }
	return $$cache{dirs}{$dir};
}

sub list_path { return map list_dir($_), grep {-d $_} @PATH }

sub unique_file {
	my $string = pop || "untitledXXXX";
	my ($file, $number) = ($string, 0);
	$file =~ s/XXXX/$number/;
	while ( -e $file ) {
		if ($number > 256) {
			$file = undef;
			last;
		} # infinite loop protection
		else {
			$file = $string;
			$file =~ s/XXXX/$number/;
		}
		$number++
	};
	die qq/could not find any non-existent file for string "$string"/
		unless defined $file;
	return $file;
}

## Engine routines ##

sub index_path { read_dir($_, 1) for grep {-d $_} @PATH }

sub wipe_cache { 
	foreach my $dir (keys %{$$cache{dirs}})  {
		next if $$cache{dirs}{$dir}{no_wipe};
		my $diff = time - $$cache{dirs}{$dir}{cache_atime};
		delete $$cache{dirs}{$dir} if $diff > $cache_atime;
	}
}

sub read_cache {
	my $file = _shift_file(@_);
	return unless $_storable;
	eval { $cache = lock_retrieve($file) } if -s $file;
	$cache = { VERSION => $VERSION } unless $$cache{VERSION} eq $VERSION;
}

sub save_cache {
	my $file = _shift_file(@_);
	return unless $_storable;
	lock_store($cache, $file);
}

sub _shift_file {
	my $file = pop || $dump_file;
        if ( !$file || ref $file) { die 'Got no valid filename.' }
        $dump_file = $file; # memorise it
	return $file;
}

1;

__END__

=pod

=head1 NAME

Zoidberg::Utils::FileSystem - filesystem routines

=head1 DESCRIPTION

This module contains a few routines dealing with files and/or directories.
Mainly used to speed up searching $ENV{PATH} by "hashing" the filesystem.

Although when working within the Zoidberg framework this module should be used through
the L<Zoidberg::Utils> interface, it also can be used on it's own.

=head1 EXPORT

By default none, potentially all functions listed below.

=head1 FUNCTIONS

=over 4

=item C<abs_path($file, $reference)>

Returns the absolute path for possible relative C<$file>
C<$reference> is optional an defaults to C<$ENV{PWD}>

=item C<list_dir($dir)>

Returns list of content of dir.
This is B<not> simply an alias for C<readdir> but uses caching.

=item C<list_path()>

Returns a list of all items found in directories listed in C<$ENV{PATH}>,
non existing directories in C<$ENV{PATH}> are silently ignored.

=back

=head1 AUTHOR

R.L. Zwart E<lt>rlzwart@cpan.orgE<gt>

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>
L<Zoidberg::Utils>

=cut

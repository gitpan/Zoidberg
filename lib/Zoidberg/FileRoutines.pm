package Zoidberg::FileRoutines;

our $VERSION = '0.40';

use strict;
#use File::Spec;
use Carp;
use Env qw/@PATH/;
use Storable qw(lock_store lock_retrieve);
use File::Spec; # TODO make more use of this lib
use Zoidberg::Utils qw/debug/;
use Exporter::Tidy
	engine     => [qw/index_path wipe_cache read_cache save_cache/],
	basic      => [qw/abs_path list_path get_dir unique_file $DEVNULL/],
	exec_scope => [qw/abs_path get_dir list_path $DEVNULL/],
	other      => [qw/is_exec_in_path/];

our $cache = {};
our $cache_time = 300; # 5x60 -- 5 minutes
our $dump_file = '';

our $DEVNULL = File::Spec->devnull();

#############################
#### Basic file routines ####
#############################

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

sub get_dir {
	my $dir = shift || $ENV{PWD};
	unless ($cache->{dirs}{$dir}) { $dir = abs_path($dir); }
	
	my $mtime = (stat($dir))[9];
	read_dir($dir, @_) unless $cache->{dirs}{$dir} && ($mtime == $cache->{dirs}{$dir}{mtime});
	$cache->{dirs}{$dir}{cache_time} = time;
	
	return $cache->{dirs}{$dir};
}

sub read_dir {
	my $dir = shift;
	debug "(re-) scanning directory: $dir";
	if (-e $dir) {
		my $no_wipe = shift || $cache->{dirs}{$dir}{no_wipe};
		$cache->{dirs}{$dir} = {
			'path' => $dir,
			'files' => [],
			'dirs' => [],
			'mtime' => (stat($dir))[9],
			'no_wipe' => $no_wipe,
		};
		$cache->{dirs}{$dir}{path} =~ s#/?$#/#;
		opendir DIR, $dir;
		my $item;
		while ($item = readdir DIR) {
			next if $item =~ /^\.{1,2}$/;
			if (-d $dir.'/'.$item  || -d readlink($dir.'/'.$item)) { 
				push @{$cache->{dirs}{$dir}{dirs}}, $item;
			}
			else { push @{$cache->{dirs}{$dir}{files}}, $item }
		}
		closedir DIR;
		$cache->{dirs}{$dir}{cache_time} = time;
	}
	else { croak "no such dir $dir" }
	return $cache->{dirs}{$dir};
}

sub list_path { return map { @{&get_dir($_)->{files}} } grep { -d $_ } @PATH }

sub is_exec_in_path {
	my $cmd = shift;
	my $file;
	for my $dir (@PATH) {
		next unless -d $dir;
		($file) = grep { -x $_ }
			map  { $dir.'/'.$_ }
			grep { $_ eq $cmd  }
			@{&get_dir($dir)->{files}};
		return $file if $file;
	}
}

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

#########################
#### Engine routines ####
#########################

sub index_path { foreach my $dir (grep {-e $_} @PATH) { read_dir($dir, 1) } }

sub wipe_cache { 
	foreach my $dir (keys %{$cache->{dirs}})  {
		unless ($cache->{dirs}{$dir}{no_wipe}) {
			my $diff = time - $cache->{dirs}{$dir}{cache_time};
			if ($diff > $cache_time) { delete ${$cache->{dirs}}{$dir} }
		}
	}
}

sub read_cache {
	my $file = _shift_file(@_);
	if (-s $file) { $cache = lock_retrieve($file); } # _our_ $cache
}

sub save_cache {
	my $file = _shift_file(@_);
	lock_store($cache, $file);
}

sub _shift_file {
	my $file = pop || $dump_file; # $Zoidberg::FileRoutines::dump_file
        if ( !$file || ref $file) { die 'Got no valid filename.' }
        $dump_file = $file; # memorise it
	return $file;
}

1;

__END__

=pod

=head1 NAME

Zoidberg::FileRoutines - file handling utils for Zoidberg

=head1 DESCRIPTION

This module contains a few routines dealing with files and/or directories.
Mainly used to speed up searching $ENV{PATH} by "hashing" the filesystem.

=head1 EXPORT

By default none, potentially all functions listed below.

=head1 FUNCTIONS

=over 4

=item C<abs_path($file, $reference)>

Returns the absolute path for possible relative C<$file>
C<$reference> is optional an defaults to C<$ENV{PWD}>

=item C<get_dir($dir)>

Returns contents of $dir as a hash ref containing :
	'files' => [@files],
	'dirs' => [@dirs],
Array files contains everything that ain't a dir.

=item C<list_path()>

Returns a list of all the files found in directories listed in C<$ENV{PATH}>.
Non existing directories in C<$ENV{PATH}> are silently ignored.

=item C<is_exec_in_path($cmd)>

Returns absolute path if C<$cmd> exists in a directory listed in C<$ENV{PATH}>
and is executable. If C<$cmd> can't be found or isn't executable undef is returned.

=back

=head1 TODO

This module could benefit from using C<tie()>.

=head1 AUTHOR

R.L. Zwart E<lt>rlzwart@cpan.orgE<gt>

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

=cut

package Zoidberg::FileRoutines;

require Exporter;

use File::Spec;
use strict;

push @{Zoidberg::FileRoutines::ISA}, 'Exporter';

@{Zoidberg::FileRoutines::EXPORT_OK} = qw/abs_path cache_path list_path scan_dir read_dir is_executable unique_file wipe_cache $cache/;
%{Zoidberg::FileRoutines::EXPORT_TAGS} = (
	zoid_compat => [qw/abs_path cache_path list_path scan_dir is_executable unique_file wipe_cache/],
	exec_scope  => [qw/abs_path scan_dir is_executable/],
);

our $cache = {};

our $cache_time = 300;

########################################
#### File routines -- do they belong in this object ? #### no they don't!
########################################

sub abs_path {
	# return absolute path
	# argument: string optional: reference
	my $string = shift || return $ENV{PWD};
	my $refer = $_[0] ? abs_path(shift @_) : $ENV{PWD}; # possibly recurs
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
	my $ding = shift;
	@{$cache->{path_dirs}} = grep {-d $_} grep {($_ ne '..') && ($_ ne '.') && (!/^\.+\//)} split (/:/, $ENV{PATH});
	foreach my $dir (@{$cache->{path_dirs}}) { scan_dir($dir, $ding, 1); }
}

sub list_path {
	my @return = ();
	foreach my $dir (@{$cache->{path_dirs}}) { push @return, grep {-x $dir.'/'.$_} @{$cache->{dirs}{$dir}{files}}; }
	return [@return];
}

sub scan_dir {
	my $dir = shift || $ENV{PWD};
	my ($string, $no_wipe) = @_;
	unless ($cache->{dirs}{$dir}) { $dir = abs_path($dir); }
	my $mtime = (stat($dir))[9];
	unless ($cache->{dirs}{$dir} && ($string ne 'force') && ($mtime == $cache->{dirs}{$dir}{mtime})) {
		read_dir($dir, $no_wipe);
	}
	else { $cache->{dirs}{$dir}{cache_time} = time; }
	return $cache->{dirs}{$dir};
}

sub read_dir {
	my $dir = shift;
	if (-e $dir) {
		my $no_wipe = shift || $cache->{dirs}{$dir}{no_wipe};
		opendir DIR, $dir;
		my @contents = readdir DIR;
		splice(@contents, 0, 2); # . && ..
		closedir DIR;
		chdir $dir;
		my @files = grep {-f $_ || -f readlink($_)} @contents;
		my @dirs = grep {-d $_  || -d readlink($_)} @contents;
		my @rest = grep { !(grep $_, @files) && !(grep $_, @dirs) } @contents;
		chdir($ENV{PWD});
		$cache->{dirs}{$dir} = { 
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
	my $name = pop;
	if (-x $name) { return 1; }
	elsif (grep {/^$name$/} @{&list_path}) { return 1; }
	else {return 0; }
}

sub unique_file {
	my $string = pop || "untitledXXXX";
	my $file;
	my $number = 0;
	$file = $string;
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
	}
	unless (defined $file) { die "could not find any non-existent file for string \"$string\"" }
	return $file;
}

sub wipe_cache {
	foreach my $dir (keys %{$cache->{dirs}})  {
		unless ($cache->{dirs}{$dir}{no_wipe}) {
			my $diff = $cache->{dirs}{$dir}{cache_time} - time;
			if ($diff > $cache_time) { delete ${$cache->{dirs}}{$dir}; }
		}
	}
}

sub glob {
}

1;
__END__

=pod

=head1 FUNCTIONS

=item B<abs_path($file, $reference)>

  Returns the absolute path for possible relative $file
  $reference is optional an defaults to $ENV{PWD}

=item B<scan_dir($dir)>

  Returns contents of $dir as a hash ref containing :
	'files' => [@files],
	'dirs' => [@dirs],
	'rest' => [@rest],
  'rest' are all files that are not (a symlink to) a file or dir



package Makefile;

our $VERSION = 0.1;

use strict;
use Config;
use Carp;
use Storable qw/dclone/;
require Exporter;
use Data::Dumper;

$Data::Dumper::Purity=1;
$Data::Dumper::Deparse=1;
$Data::Dumper::Indent=1;


push @{Makefile::ISA}, 'Exporter';
@{Makefile::EXPORT_OK} = qw/
	get_version get_version_from compare_version
	path_copy file_copy
	rmdir_force dir_copy pd_read chdir
	pd_write
/;

our %default_config = (
	'default_target' => 'all',
	'conf_file' => 'm/config.pd',
	'makefile' => 'Makefile',
	'target_dir' => 'm/targets',
	'manifest' => 'MANIFEST',
	'tools' => {
		# name => [ command, [extensions] ]
		'perl' =>  [ $Config{perl5}, ['pl', 'PL', 'pm'] ],
		'shell' => [ $Config{sh},    [ 'sh' ]           ],
	}
);

our @var_arg = @ARGV; # copy here - use later

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	my $config = shift || $default_config{conf_file};

	unless (ref($config)) {
		my $file = $config;
		$config = {};
		if (-f $file) { $config = $self->pd_read($file); }
		$config->{conf_file} = $file;
	}

	$self = bless $config, $class; 
	#<VUNZIG>
	foreach (keys %default_config) { unless ($self->{$_}) { $self->{$_} = $default_config{$_}; } }
	foreach (keys %{$default_config{vars}}) { unless ($self->{vars}{$_}) { $self->{vars}{$_} = $default_config{vars}->{$_}; } }
	foreach (keys %{$default_config{tools}}) { unless ($self->{tools}{$_}) { $self->{tools}{$_} = $default_config{tools}->{$_}; } }

	my %tmp;
	for (keys %{$self->{vars}}) { $tmp{uc($_)} = $self->{vars}{$_}; }
	$self->{vars} = \%tmp;
	my %tmp1;
	for (keys %{$self->{tools}}) { $tmp1{uc($_)} = $self->{tools}{$_}; }
	$self->{tools} = \%tmp1;
	#</VUNZIG>

	if ($0 !~ /(Makefile\.PL|configure)$/) {
		if (@var_arg) {# reverse serialised vars
			for (0..$#{$self->{var_order}}) { $self->{vars}{$self->{var_order}[$_]} = $var_arg[$_] || ''; }
		}
	}
	else {
		if (@var_arg) { #print "debug vars: -".join('-', @var_arg)."-\n";
			for (@var_arg) { # parse gnu style args
				#print "debug var: -$_-\n";
				#$_ =~ s/^--?//;
				if ($_ =~ m/^-{0,2}(\w*)=[\"\']?(.*)[\"\']?$/) { 
					if (exists $self->{$1}) { $self->{$1} = $2; }
					else { $self->{vars}{uc($1)} = $2; }
				}
				elsif ($_ =~ m/^(--usage|--help|-u|-h)$/) {
					$self->print_usage;
					exit 0;
				}
				else {
					print "Unknown or wrongly formatted option \"$_\"\nTry \"--usage\" for help text.\n";
					exit 1;
				}
			}
		}
	}

	return $self;
}

sub pd_read {
	my $file = pop;
	open FILE, "<$file" || die "==> Could not open file $file\n";
	my $cont = join("",(<FILE>));
	close FILE;
	my $VAR1;
	eval($cont);
	if ($@) { die "Failed to eval the contents of $file ($@).\n"; }
	return $VAR1;
}

sub pd_write {
	my $ref = pop;
	my $file = pop;
	open FILE, ">$file" || die "==> Could not open file $file\n";
	print FILE Dumper($ref);
	close FILE || die "==> Could not write file $file\n";
}

sub check_manifest {
	my $self = shift;
	$self->{manifest_ok} = 1;
	print "debug: using manifest: $self->{manifest}\n";
	for ($self->manifest) {
		if ($self->{vars}{VERBOSE}) { print "Checking for file \"$_\".\n"; }
		unless (-f $_) {
			$self->{manifest_ok} = 0;
			print STDERR "==> The file \"$_\" seems to miss from your package.\n";
		}
	}
	if ($self->{manifest_ok}) {
		print "Manifest seems to be ok.\n";
		return 1;
	}
	else { 
		print "This package seems to be incomplete, maybe you should fetch a new source tree.\n";
		return 0;
	}
}


sub manifest {
	my $self = shift;
	my $man = shift || $self->{manifest};
	my @files = ();
	open IN, $man || die "==> Could not open $man\n";
	while (<IN>) { # FIXME what about names with whitespaces etc. ?
		next if m/^\s*#/;
		m/^\s*(.+?)(\s+#|$)/;
		push @files, $1 if $1;
	}
	close IN;
	return @files;
}

sub check_dep {
	my $self = shift;
	unless (exists $self->{include}{PREREQ_PM}) {die "No include PREREQ_PM found";}
	$self->{dep_ok} = 1;
	while (my ($module, $version) = each %{$self->{include}{PREREQ_PM}}) {
		my $our_v = get_version($module);
		if ($self->{vars}{VERBOSE}) { print "checking $module version $version we have: ".$our_v."\n"; }
		unless (defined $our_v && compare_version($version, $our_v) >= 0) {
			$self->{dep_ok} = 0 unless $our_v;
			print STDERR
				( $our_v ? 'Warning :' : '==> Failed'),
				qq{ dependency "$module" },
				($version ? "version $version" : ''),
				($our_v ? " suggested - we have $our_v\n" : "\n");
		}
	}
	if ($self->{dep_ok}) {
		print "Dependencies seem to be ok.\n";
		return 1;
	}
	else {
		print "Some dependecies failed, you should install these packages first.\n";
		return 0;
	}
}

sub write_makefile {
	my $self = shift;

	# var order is random but should be known for serialisation
	unless ($self->{var_order}) { $self->{var_order} = [ keys %{$self->{vars}} ]; }

	$self->{target_dir} =~ s/\/$//; #/

	opendir TD, $self->{target_dir};
	my @targets = map { # according to damian these kind of constructs are evil :]
		my $name = $_;
		$name =~ s/\.(.*)$//;
		my $file = $self->{target_dir}.'/'.$_;
		my $tool;
		if ($1) {
			($tool) = grep {grep {$1 eq $_} @{$self->{tools}{$_}[1]}} keys %{$self->{tools}};
			if ($tool) { $tool = "\@\$($tool) "; }
			else { die "Please define a command for the \".$1\" extension"; }
		}
		elsif (-d $file) {
			$file =~ s/\/?$/\//;
			opendir D, $file;
			$file = [ map {
				$_ =~ m/\.(.*?)$/;
				my $m_tool;
				if ($1) {
					($m_tool) = grep {grep {$1 eq $_} @{$self->{tools}{$_}[1]}} keys %{$self->{tools}};
					if ($m_tool) { $m_tool = "\@\$($m_tool) "; }
					else { die "Please define a command for the \".$1\" extension" }
				}
				[$file.$_, $m_tool];
			} sort grep {$_ !~ m/^(\.\.?|CVS)$/} (readdir D) ];
			closedir D;
		}
		elsif (-x $file) { $file = "\@".$file; }
		else { die "Shouldn't \"$file\" be executable ?"}
		[$name, $file, $tool];
	} grep {$_ !~ m/^(\.\.?|CVS)$/} (readdir TD);
	closedir TD;
	push @targets, map { [$_, undef, undef] } @{$self->{fake_targets}};

	my ($def) = grep {$_->[0] eq $self->{default_target}} @targets;
	@targets = grep {$_->[0] ne $self->{default_target}} @targets;
	unshift @targets, $def;

	$self->{target_names} =  [ map {$_->[0]} @targets ];

	#if (-e $self->{makefile}) { unlink $self->{makefile}; }
	open FILE, '>'.$self->{makefile} || die '==> Could not open '.$self->{makefile}."\n";
	print FILE "## This Makefile was autogenerated by Makefile.pm\n## Dont try to change anything here, change the perl scripts\n\n";

	print FILE "#--[ Included data ]--[ some of this might be used by CPAN ]\n\n";
	for (keys %{$self->{include}}) { print FILE "#\t".$_." => ".$self->serialize($self->{include}{$_})."\n"; }

	print FILE "\n#--[ Tools ]\n\n";
	for (keys %{$self->{tools}}) { unless (exists $self->{vars}{$_}) { print FILE $_." = ".$self->{tools}{$_}[0]."\n"; } }

	print FILE "\n#--[ Config vars ]\n\n";
	for (@{$self->{var_order}}) { print FILE $_." = ".$self->{vars}{$_}."\n"; }

	print FILE "\n#--[ Phony targets ]--[ targets dir is \"$self->{target_dir}\" ]\n\n";
	print FILE '.PHONY : '.join(' ', (map {$_->[0]} @targets))."\n\n";

	#my $arg = join(' ', map {'"$('.uc($_).')"'} @{$self->{var_order}});
	print FILE '_ARGS = '.join(' ', map {'"$('.uc($_).')"'} @{$self->{var_order}})."\n\n";
	my $arg = '$(_ARGS)';

	foreach my $t (@targets) {
		my $dep = $self->{depends}{$t->[0]} ? join(' ', @{$self->{depends}{$t->[0]}}) : '' ;
		if (!defined $t->[1]) { print FILE "$t->[0] : $dep\n\n"; }
		elsif (ref($t->[1]) eq 'ARRAY') { print FILE "$t->[0] : $dep\n\t".join("\n\t", map {$_->[1].$_->[0]." ".$arg} @{$t->[1]})."\n\n"; }
		elsif ($t->[1]) { print FILE "$t->[0] : $dep\n\t".$t->[2].$t->[1]." $arg\n\n"; }
		else { die "Don't know what to do with target \"$t->[0]\", \"$t->[1]\"\n"; }
	}

	my $my_file = __FILE__;
	my $my_mani = $self->{manifest};

	print FILE << "END"
#--[ basic check ]

Makefile : Makefile.PL $my_file
	\@echo "==> Your Makefile.PL or $my_file is newer then your Makefile."
	\@echo "==> Run perl Makefile.PL first."
	\@false

END
;
	close FILE || die '==> Could not write'.$self->{makefile}."\n";

	my $spec = '...';
	if ($self->{include}{NAME}) {
		$spec = "for ".$self->{include}{NAME};
		if ($self->{include}{VERSION}) { $spec .= " version ".$self->{include}{VERSION}; }
	}

	# write fresh config
	$self->pd_write($self->{conf_file}, $self);

	print "Wrote new Makefile $spec\n";

	return 1;
}

sub serialize { # recursive
	my $self = shift;
	my $ding = shift;
	if (ref($ding) eq 'ARRAY') {
		return '['.join(', ', map {$self->serialize($_)} @{$ding}).']';
	}
	elsif (ref($ding) eq 'HASH') {
		return '{'.join(', ', map {$_.'=>'.$self->serialize($ding->{$_})} keys %{$ding}).'}';
	}
	else {
		$ding =~ s/([\[\]])/\\$1/g;
		return 'q['.$ding.']';
	}
}

sub print_usage {
	my $self = shift;
	my $name = $self->{include}{NAME} || 'unknown';
	my $version = $self->{include}{VERSION} || 'unknown';
	my $author = $self->{include}{AUTHOR} || 'unknown';
	print << "END";

## This package uses Makefile.pm - yet another approach to Makefile.PL
## by Jaap Karssenberg || Pardus [Larus] -=- 2003

--[ Package information ]

 NAME    : $name
 VERSION : $version
 AUTHOR  : $author

--[ Usage ]

  > perl Makefile.PL [options] [VAR1=value] [VAR2=value]

--[ Options ]

  --usage, --help, -u, -h Print this text.

--[ Variables ]

END

	for (keys %{$self->{vars}}) { 
		print '  ', $_, ($self->{vars}{$_} ? ' :  '.$self->{vars}{$_} : ''), "\n"; 
	}
	print "\n\n";
}

sub compare_version {
	my $gr = pop || 0;
	my $ls = pop || 0;
	if ($gr eq  $ls) { return 0; }
	$gr =~ s/^v//i;
	$ls =~ s/^v//i;
	my @gr = split(/\./, $gr);
	my @ls = split(/\./, $ls);
	#print "DEBUG: gr: -".join('-', @gr)."- ls: -".join('-', @ls)."-\n";
	foreach my $i (0..$#gr) {
		if ($gr[$i] eq $ls[$i]) { next; }
		my @m_gr = split(//, $gr[$i]);
		my @m_ls = split(//, $ls[$i]);
		foreach my $j (0..$#m_gr) {
			if ($m_gr[$j] eq $m_ls[$j]) { next; }
			return ($m_gr[$j] <=> $m_ls[$j]);
		}
		if ($#m_ls > $#m_gr) { return -1; }
		else { return 1; }
	}
	if ($#ls > $#gr) { return -1; }
	else { return 1; }
}

sub get_version {
	my $name = pop @_;
	my $file;
	unless ($name =~ m{/}) {
		$name =~ s/\(.*\)$//;
		$file = $name.'.pm';
		$file =~ s{::}{/}g;
	}
	else { $file = $name }
	if ($INC{$file}) { $file = $INC{$file} }
	else {
		for (@INC) { # get absolute path
			next unless -f $_.'/'.$file;
			$file = $_.'/'.$file;
			last;
		}
	}
	return undef unless -f $file;
	return get_version_from($file) || 0;
}

sub get_version_from {
	# Code borrowed from ExtUtils::MM_Unix
	my $file = pop;
	my $inpod = 0;
	my $result = undef;
	open IN, $file || die "==> Could not open file $file\n";
	while (<IN>) {
		$inpod = /^=(?!cut)/ ? 1 : /^=cut/ ? 0 : $inpod;
		next if $inpod || /^\s*#/;
		next unless /([\$*])(([\w\:\']*)\bVERSION)\b.*\=/;
		my $eval = qq{
			package Makefile::_version;
			no strict;

			local $1$2;
			\$$2=undef; 
			$_
			\$$2
        	};
		local $^W = 0;
		$result = eval($eval);
		print STDERR "Warning: Could not eval '$eval' in $file: $@" if $@;
		last;
	}
	close IN || die "==> Could not read file $file\n";
	return $result;
}

sub path_copy {
	my $e = 'usage: path_copy $from, $to';
	my $to = pop @_ || die $e;
	my $from = pop @_ || die $e;
	unless (-e $from) { confess "no such thing \"$from\" to copy"; }

	# create dir tee
	if ($to =~ m/^(.*)\/(.*)/) {
		my @tree = split(/\//, $1);
		my $dir = '';
		while (@tree) {
			$dir .= (shift @tree).'/';
			unless (-d $dir) { mkdir $dir }
		}
	}

	return file_copy($from, $to);
}

sub file_copy {
	my $e = 'usage: file_copy $from, $to;';
	my $to = pop @_ || die $e;
	my $from = pop @_ || die $e;
	unless (-e $from) { die "no such thing \"$from\" to copy"; }

	if (
		( [stat $from]->[9] == [stat $to]->[9] )
		&& ( -s $from == -s $to )
	) { return 1 }
        
	open IN, $from || die "==> Could not open file $from\n";
	open OUT, ">$to" || die "==> Could not open file $to\n";
	while (<IN>) { print OUT $_; }
	close IN;
	close OUT || die "==> Could not write file $to\n";
    # set new file's mtime
    utime(@{[stat$from]}[8,9],$to);
	return 1;
}

sub rmdir_force {
	my $dir = pop || die 'usage: rmdir_force $dir;';
	$dir =~ s/\/$//; #/
	unless (-e $dir) { return 1; }
	opendir D, $dir || die "==> Could not open dir $dir\n";
	my @dinge = grep {$_ !~ m/^\.\.?$/} readdir D;
	closedir D;
	for (grep { !(-d $dir.'/'.$_) } @dinge) { unlink $dir.'/'.$_ || die "==> Could not remove $dir/$_\n" }
	for (grep { -d $dir.'/'.$_ } @dinge) { rmdir_force($dir.'/'.$_) } # recurs
	return rmdir $dir;
}

sub dir_copy {
	# dir from, dir to
	my $e = 'usage: dir_copy $from, $to;';
	my $to = pop || die $e;
	my $from = pop || die $e;

	$from =~ s/\/?$/\//;
	$to =~ s/\/?$/\//;
	unless (-e $to) { mkdir($to) || die "Could not make dir $to\n"; }

	opendir FROM, $from || die "Could not open dir $from\n";
	my @files = grep {$_ !~ m/^\.\.?$/} readdir FROM;
	closedir FROM;

	my @done = @files;

	foreach my $file (grep {-f $from.$_} @files) { file_copy($from.$file, $to.$file) }
	foreach my $dir (grep {-d $from.$_} @files) {
		push @done, dir_copy( $from.$dir, $to.$dir ); #recurs
	}

	return @done;
}

1;

__END__

=head1 NAME

Makefile - yet another approach to Makefile.PL

=head1 SYNOPSIS

in F<Makefile.PL>

  require 'm/Makefile.pm';
  import Makefile qw/get_version_from/;

  my %config = (
    'default_target' => 'compile',
    'manifest' => 'MANIFEST',
    'fake_targets' => [qw/all/],
    'depends' => {
        'all' => [qw/compile test install/],
    },
    'vars' => {
        'PREFIX' => '/usr/local',
        'TEST_VERBOSE' => 0,
        'CONFIG' => '/etc',
        'INSTALLDIRS' => 'site',
    },
    'include' => {
        'NAME'		=> 'My_perl_extension',
        'VERSION'	=> get_version_from('lib/My_perl_extension.pm'),
        'AUTHOR'	=> 'N. Nescio <NN@incognita.net>',
        'PREREQ_PM'	=> { 'Data::Dumper' => '1.0', 'Storable' => '0.5' },
    },
  );

  my $make = Make->new(\%config);
  $make->check_manifest;
  $make->write_makefile;

in for example F<m/targets/test.pl>

  require 'm/Makefile.pm';
  import Makefile qw/path_copy rmdir_force/;

  my $make = Makefile->new;

  use Test::Harness;
  $Test::Harness::verbose = $make->{vars}{TEST_VERBOSE};

  # run tests etc ...

=head1 DESCRIPTION

This module is yet another approach to the make process for
packages of perl files. It does as little as possible in the makefile
itself but rather links make targets to perl scripts.

By default the scripts are in a directory F<m/targets>. These scripts can be of a general/reusable
kind but also can contain package specific code. The scripts also
can use this module to get their configuration vars.

One can add make targets by simply adding scripts or directories to the target directory.

For obvious reasons it is not possible to have a target called 'CVS' --
'cvs' or any combination with it should work fine. Also it is not wise to call a target
'Makefile' or something alike. Since Makefile.pm relies on @ARGV one should not touch
@ARGV in a target script or at least do C<require 'm/Makefile.pm';> first.

Also since the module itself just glues scripts in the Makefile, it can also be used for
all kind of packages other then perl extensions.

This module is not intended for permanent installation,
it should be included in the package, by default as F<m/Makefile.pm>.

=head2 EXPORT

None by default

All routines marked as "non oo method" are in @EXPORT_OK .
These exports can be used by target script for some standard functionality.

=head1 CONFIG

The config hash contains the following keys. These can be set before writing the makefile
and can be accessed in the target scripts as attributes of the Makefile object.

It is adviced to do something like C<%config = ( 'file' => $ENV{PWD}.'/file', );> in Makefile.PL
to make sure target scripts even find the meta files after doing chdir or something similar.

=over 4

=item conf_file

Makefile.pm's config file, defaults to 'm/config.pd', if you choose an other config file
you should also modify all target scripts form C<Makefile->new> to C<Makefile->new({ 'conf_file' => 'my_conf_file'})>

=item makefile

The name of the created makefile, defaults to 'Makefile'.

=item target_dir

Dir to scan for targets, defaults to 'm/targets'. All files and dirs in this dir will be regarded as
make targets except dirs called 'CVS'.

=item default_target

Supply to target to be executed when make is run without args, defaults to 'all'.

=item manifest

Name of your manifest file, defaults to 'MANIFEST'.
Most of my target scripts rely heavely on the manifest to be correct.

=item fake_targets

Array ref of target names without scripts asociated to them. In combination with "depends" used to bundle targets.

=item depends

Hash ref with target names as keys and arra refs as values. Array contains names of targets the key target
depends on. Can be used to bundle targets.

=item vars

Vars should be a hash ref with of the form C<{ var_name => default_value, }>. Values
should always be strings. Var names will be translated to all caps - to acces them from
targets scripts use this last form. The var "VERBOSE" is special.

Vars can be commandline args to make like: C<make test TEST_VERBOSE=1> and the defaults can be
set both from the Makefile.PL (in the config hash) and as commandline args to Makefile.PL like: C<perl Makefile.PL test_verbose=1>,
C<perl Makefile.PL --test_verbose="1"> or C<perl Makefile.PL TEST_VERBOSE=1>.

=item include

Hash ref with package information. Used for several purposes and will be included in the Makefile as comment.
For example CPAN reads dependencies from these comments.

At least provide: 'NAME', 'VERSION', 'AUTHOR' and 'PREREQ_PM' to provide package data.

The first 3 take a string, PREREQ_PM takes a hash ref with module names as keys and version numbers as values.
PREREQ_PM specifies the dependencies.

Modelled after C<ExtUtils::MakeMaker> vars.

=item help

Hash ref, has target names as keys and a string as value, this string is used by the print_help method.

=item help_postamble

String to be printed as part of the help text with print_help.

=item tools

Hash ref that tells Makefile.pm which interpreter to use for which extension. Also these create vars in the Makefile
that can be overloaded with commandline args.

Entries have their var name as key (like vars this is set to caps) and as value an array consisting of the
interpreter binary location and a array of possible file extensions. This will asociate these extensions 
with the given interpreter and allows you to supply alternate interpreter locations as commandline arguments.

This hash defaults to C<{ 'PERL' => [ $Config{perl5}, ['pl', 'PL', 'pm'] ], 'SHELL' => [ $Config{sh}, ['sh'] ], }>

=back

=head1 METHODS

=over 4

=item C<new(\%config)>

Simple constructor, takes config hashref. If no config is supplyed
tries to read the default config file and/or uses default config.

Most likely one only supplies config from the F<Makefile.PL>.

=item C<pd_read($file)>

Eval $file and return $VAR1 .

=item C<pd_write($file, \%hash)>

Print hash to file with Data::Dumper .

=item C<check_manifest()>

Check for missing files, prints errors and returns bit.

=item C<manifest()>

Reads the manifest and returns a array filenames.

=item C<check_dep()>

Check for missing dependencies, prints errors and returns bit.

=item C<write_makefile()>

Print makefile. This does _not_ create something like
a Makefile.old -- if you want this do it yourself from Makefile.PL .
Also this method writes a fresh config file used as
a bypass around the Makefile :]

=item C<compare_version($v1, $v2)> [non oo method]

Returns 0 if $v1 eq $v2, 1 if $v1 < $v2 and -1 if $v1 > $v2.
Used to compare required versions to installed versions.

=item C<get_version($class_name)> [non oo method]

Get version of an installed module.

=item C<get_version_from($file)> [non oo method]

Get version declared in file. This uses the same regex as L<ExtUtils::MakeMaker> uses for
"VERSION_FROM" this is: C</([\$*])(([\w\:\']*)\bVERSION)\b.*\=/> . See docs MM for more details.

=item C<path_copy($from, $to)> [non oo method]

Copy file $from to file $to, create directories if needed.

=item C<file_copy($from, $to)> [non oo method]

Copy file $from to file $to, create directories if needed.

=item C<rmdir_force($dir)> [non oo method]

Like C<rm -fr dir>, used to rm non-empty dir trees.
I<Use with care>.

=item C<dir_copy($from, $to)> [non oo method]

Copy contents of dir $from to dir $to

=back

=head1 LIMITATIONS

I do not intend to develope this module to
maturity, as long as it works for my package I'm
happy. (But if anyone feels like doing so ...)

I'm not sure it scales right. But this is up to your specific configuration.

It doesn't have all the fancy features like XS support, this should be implemented in target scripts,
the module is just glue. On the other hand standard routines could be put in the module.
Write your own fancy script or use MakeMaker instead.

It depends on other modules, see L</DEPENDS> . Also the scripts use other
packages like Pod::Man. This might be a problem in some situations.

I have no idea about the portability to other platforms, but one can just patch the scripts.
At least it should use File::Spec but it doesn't.

=head1 DEPENDS

 Carp
 Config
 Exporter
 Strorable
 Data::Dumper

=head1 HISTORY

This module was born as part of the zoidberg project out of a personal itch with MakeMaker.
Features where selected upon the needs of this project. See the Zoidberg for an extensive example.

I<"You all _do_ write docs, don't you?"> - Schwern on Yapc::Europe::2002

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

Example: L<Zoidberg>, L<http://zoidberg.sf.net>

Related:
L<ExtUtils::MakeMaker>,
L<CPAN::MakeMaker>,
L<Module::Build>,
L<CPAN>,
L<http://www.gnu.org/manual/make>

=cut


use strict;

require 'm/Makefile.pm';
import Makefile qw/
	pd_read
	check_mtime path_copy make_dir
	get_version get_version_from compare_version
/;

my $make = Makefile->new;

## create build dir ##
mkdir 'b', 0755 unless -d 'b';

print "Copying files to build directory.\n";

our @MANIFEST = $make->manifest;

## simply copy most files ##
for (grep m!^(\./)?(lib|doc|share|etc|t)/!, @MANIFEST) {
	next if check_mtime($_, 'b/'.$_);
	print "copying $_\n" if $make->{vars}{VERBOSE};
	path_copy($_, 'b/'.$_);
}

for (qw/README Changes Install BUGS/) {
	next if check_mtime($_, 'b/doc/'.$_);
	print "copying $_\n" if $make->{vars}{VERBOSE};
	path_copy($_, 'b/doc/'.$_);
}

## check the need for included libs ##
for my $file (grep m!^(\./)?inc/!, @MANIFEST) {
	next unless $file =~ m/\.(pl|pm)$/i;
	$file =~ m!^(?:\./)?inc/(.*)!;
	my $inst_version = get_version($1);
	my $version = get_version_from($file);
	if (
		defined $inst_version 
		and compare_version($version, $inst_version) >= 0
	) {
		print "$file skipped, is allready installed\n" if $make->{vars}{VERBOSE};
	}
	else {
		next if check_mtime($file, 'b/'.$file);
		print "copying $file\n" if $make->{vars}{VERBOSE};
		path_copy($file, 'b/'.$file);
	}
}

if ($] < 5.008) {
	# special perl version dependent case :S
	my $file = 'inc/Tie/Hash.pm';
	unless (check_mtime($file, 'b/'.$file)) {
		print "copying $file\n" if $make->{vars}{VERBOSE};
		path_copy($file, 'b/'.$file);
	}
}

## compile zoid and possibly ##
goto END_OF_ZOID_COMPILE 
	if  check_mtime('./bin/fluff',     './b/bin/zoid')
	and check_mtime('./man1/zoid.pod', './b/bin/zoid');

mkdir 'b/bin', 0755 unless -d 'b/bin';

die qq/You don't have perl !? Please set var 'PERL'\n/
	unless $make->{vars}{PERL};

open OUT, '>b/bin/zoid' || die "Could not write b/bin/zoid\n";
print OUT "#!$make->{vars}{PERL}\n";
open IN, './bin/fluff' || die "Could not read ./bin/fluff\n";
print OUT $_ for (<IN>);
close IN;
close OUT || die "Could not write b/bin/zoid\n";

chmod 0755, 'b/bin/zoid';

# compile usage text
eval qq{ use Pod::Text; };
die $@ if $@;

my $usage_parser = Pod::Text->new();

# Parse complete man page to temp file
$usage_parser->parse_from_file('./man1/zoid.pod', 'b/zoid.usage~~'); 

# append required sections to bin/zoid
my @sections = qw/synopsis options/;

open TEXT, 'b/zoid.usage~~' || die $!;
open FLUFF, '>>', 'b/bin/zoid' || die $!;

my $write = 0;
while (<TEXT>) {
	if (/^([A-Z]+)/) {
		$write = (grep {$1 eq uc($_)} @sections) ? 1 : 0;
	}

	if ($write) { 
		s/\*(\w+)\*/$1/g;
		print FLUFF $_;
	}
}

close TEXT;
close FLUFF || die $!;

END_OF_ZOID_COMPILE:

## compile AppRun ##
goto END_OF_APPRUN_COMPILE
	if ! $make->{vars}{APPDIR}
	or check_mtime('bin/AppRun', 'b/bin/AppRun');

open OUT, '>b/bin/AppRun' || die "Could not write b/bin/AppRun\n";
print OUT "#!$make->{vars}{PERL}\n";
print OUT qq/\nour \$TERM = "/, 
	$make->{vars}{TERM} || 'xterm -bg black -fg white -e',
	qq/";\n/;
open IN, './bin/AppRun' || die "Could not read ./bin/AppRun\n";
print OUT $_ for (<IN>);
close IN;
close OUT || die "Could not write b/bin/AppRun\n";

chmod 0755, 'b/bin/AppRun';

END_OF_APPRUN_COMPILE:

## mutate config ##
# schemes are qw/DEFAULT XDG_BASE_DIR RELATIVE CHOICES/
my $DATA = $make->{vars}{DATA};
my %conf = (
	rcfiles => '[ '.(
		$make->{vars}{APPDIR}
			? '"$ScriptDir/Config/zoidrc", '
			: "'$$make{vars}{CONFIG}/zoidrc', "
	).'"$ENV{HOME}/.zoidrc" ]',
	cache_dir => '$ENV{XDG_CACHE_HOME} || "$ENV{HOME}/.cache"',
	data_dirs => '[ "$ENV{HOME}/.zoid", '.(
		$make->{vars}{APPDIR} 
			? '"$ScriptDir/share", '
			: ($DATA eq '/usr/local/share/zoid' or $DATA eq '/usr/share/zoid')
				? ''
				: "'$DATA', "
	).q{'/usr/local/share/zoid', '/usr/share/zoid' ]},
);

open IN, 'lib/Zoidberg/Config.pm' || die $!;
open CONF, '>', 'b/lib/Zoidberg/Config.pm' || die $!;
print CONF $_ for (<IN>);
close IN || die $!;
print CONF 'our %settings = (', "\n";
print CONF "\t$_ => $conf{$_},\n" for keys %conf;
print CONF ");\n\n1;\n";
close CONF || die $!;

print "Config mutated.\n";

## compile 00_use_ok.t ##
unless (check_mtime('m/use_ok.pd', './b/t/00_use_ok.t')) {
	my $packages = pd_read('m/use_ok.pd');
	my @packages = @{$packages->{core}};

	my $body = 'use Test::More tests => '.scalar(@packages).";\n";
	$body .= "use_ok('$_');\n" for sort @packages;

	open TEST, '>', './b/t/00_use_ok.t' || die "could not open ./b/t/use_ok.t for writing";
	print TEST $body, "\n";
	close TEST || die "could not open ./b/t/use_ok.t for writing";

	print "Created a t/00_use_ok.t file\n";
}

## create 'echo' command for test ##
open BIN, '>b/t/echo' || die "could not open ./b/t/echo for writing";
print BIN '#!', $make->{vars}{PERL}, "\n", 'print join(q/ /, @ARGV), "\n";', "\n";
close BIN || die "could not open ./b/t/echo for writing";
chmod 0755, 'b/t/echo';

## compile manpages ##
use Pod::Man;

print "Creating man pages.\n";

my $version = $make->{include}{VERSION} || undef;

# parse .pod man pages
foreach my $section (1..9) {
	next unless -d "man".$section;
	mkdir "b/man".$section, 0755 unless -d "b/man".$section;

	my $parser = Pod::Man->new(
		release => "Zoidberg $version", 
		section => $section,
		center => '');

	for (grep m!^(?:\./)?man$section/!, @MANIFEST) {
		my $file = $_;
		if ($file =~ s/(\.pod)$//i) {
			next if check_mtime($file.$1, "b/$file.$section");
			print "Manifying $file$1\n" if $make->{vars}{VERBOSE};
			$parser->parse_from_file($file.$1, "b/$file.$section");
		}
		else {
			next if check_mtime($file, "b/$file");
			print "Copying $file\n" if $make->{vars}{VERBOSE};
			path_copy($file, "b/$file");
		}
	}
}

# parse module pods
my $pod_parser = Pod::Man->new(
	release => "Zoidberg $version",
	section => 3);

mkdir "b/man3", 0755 unless -d "b/man3";

for (@MANIFEST) {
	next unless m/^(?:\.\/)?lib\/(.*?)\.(pm|pod)$/i;
	my $name = $1;
	$name =~ s!/!::!g;
	next if check_mtime($_, "b/man3/$name.3pm");
	print "Manifying $_\n" if $make->{vars}{VERBOSE};
	$pod_parser->parse_from_file ($_, "b/man3/$name.3pm");
}

## compile html docs ##
goto END_HTML_DOC_COMPILE unless $make->{vars}{MAN2HTML};

print "Generating html docs.\n";

# man2html
chdir 'b' || die $!;

eval qq{
	use Pod::Html;
	use Pod::Find qw/contains_pod/;
};
die $@ if $@;

htmllify('man1/', 'doc/man1/');
htmllify('lib/', 'doc/man3/');

# compile index.html
chdir 'doc' || die $!;

make_index(
	'index.html',
	['man1', 'Section 1 - user documentation'],
	['man3', 'Section 3 - module documentation'],
);

chdir '../..';

END_HTML_DOC_COMPILE:

exit 0; # THE_END #

## various subroutines ##

sub htmllify {
	my ($from, $to) = @_;
	$from =~ s#/?$#/#;

	print "scanning dir $from\n" if $make->{vars}{VERBOSE};

	make_dir($to);

	foreach my $pod (
		map {s/^(\.\/)?$from//; $_}
		grep /^(\.\/)?$from/, 
		@MANIFEST
	) {
		next unless contains_pod("../$from/$pod");
		
		my $out_file = $pod;
		$out_file =~ s/(\.\w+)?$/.html/;
		$out_file =~ s#/#::#g;

		print " $from/$pod => $to/$out_file\n" if $make->{vars}{VERBOSE};

		my @opt = (
			"--backlink=Top",
			"--index",
			"--css=/docs.css",
			"--htmldir=doc/",
			"--libpods=perlfunc:perlvar",
			"--podpath=../$from:lib",
			"--infile=../$from/$pod",
			"--outfile=$to/$out_file",
			"--recurse",
			"--quiet",
		);

		open SAVERR, '>&STDERR';
		open STDERR, '>/dev/null';
		# pod2html trows all kind of ugly warnings
		eval { pod2html(@opt) };
		open STDERR, '>&SAVERR';
		die $@ if $@;
	}
}

sub make_index {
	my ($file, @dirs) = @_;
	
	# create index
	my $index = "<table width=100%>\n";
	for (@dirs) {
		my ($dir, $title) = @$_;
		$index .=
			"<tr><td colspan=4>&nbsp;</td></tr>\n" .
			"<tr><td colspan=4><h3>$title</h3></td></tr>\n";
		for my $file (get_files($dir)) {
			my $name = $file;
			$name =~ s/\.\w+$//;
			my $desc = get_desc("$dir/$file");
			$index .=
				"<tr><td width=10%>&nbsp;</td>" .
				"<td><a href='$dir/$file'>$name</a></td>" .
				#"<td width=5%>&nbsp;</td>".
				"<td><small>$desc</small></td>".
				"</tr>\n";
		}
	}
	$index .= "</table>\n";
	
	#write file
	open IN, $file || die "could not read $file";
	my $body = join '', (<IN>);
	close IN;
	
	$body =~ s/<!--index-->/$index/ ;

	open IN, '>', $file || die "could not write $file";
	print IN $body;
	close IN || die "could not write $file";
}

sub get_desc {
	my $file = shift;
	my $desc;
	open IN, $file || die "failed to open $file";
	while (<IN>) {
		next unless m#<title>(.*?)</title>#;
		(undef, $desc) = split /\s+-\s+/, $1, 2;
		last;
	}
	close IN;
	$desc =~ s/^\s+|\s+$//g;
	return $desc;
}

sub get_files {
	my $dir = shift;
	opendir DIR, $dir || die "could not open dir $dir";
	my @f = sort grep {$_ !~ /^\.\.?$/} readdir DIR;
	closedir DIR;
	return @f;
}

__END__


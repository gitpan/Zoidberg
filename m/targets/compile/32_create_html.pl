
require 'm/Makefile.pm';
import Makefile qw/path_copy rmdir_force/;

my $make = Makefile->new;

exit 0 if $make->{vars}{NOHTML};
my $man2html = $make->{vars}{MAN2HTML} || 0;

print "Generating html docs.\n";

chdir 'b' || die $!;

use Pod::Html;
use Pod::Find qw(pod_find);

# generate html
&doe_dir('doc/pod/');

if ($man2html) {
	foreach my $section (1..9) {
	        unless (-d "../man".$section) { next; }
		&doe_dir("../man".$section, "man".$section);
	}
	&doe_dir('lib/', 'man3pm/', 1);
}

# generate html index
chdir 'doc/html';

my @dirs = grep { -d $_ && -e $_.'/index.html' } list_dir('.');

#print "debug: dirs".join(' ', @dirs)."\n";

# create sub indexes and do some linking
foreach my $dir (@dirs) { 
	chdir $dir ;
	#print "debug dir = $dir\n";

	my $body = get_file('index.html');
	my @files = ();
	$body =~ s{\Q<!--INDEX \E(.*?)\Q-->\E}{
		@files = split(/\s+/, $1);
		#print "debug: files".join(' ', @files)."\n";
		my $index = "<ul>\n";
		for (@files) { 
			$index .= "<li><a name='$_' href='./$_.html'>$_</a></li>".get_index('./'.$_.'.html')."\n";
		}
		$index."</ul>"
	}gse;
	$body =~ s{<a href="#__index__"><small>Top</small></a>}{<small>[<a href="#__index__">Top</a>]</small>}sg;
	$body =~ s{<!--UP-->(\s*<p>\s*<small>)?}{'<p><small>[<a href=\'../index.html\'>Up</a>]'.( $1 ? ' | ' : '</small></p>')}esg;
	write_file('index.html', $body);
	
	foreach my $i (0..$#files) {
		my $file = $files[$i].'.html';
		my $body = get_file($file);
		$body =~ s{<a href="#__index__"><small>Top</small></a>}{<small>[<a href="#__index__">Top</a>]</small>}sg;
		$body =~ s{<!--PREV-INDEX-NEXT-->(\s*<p>\s*<small>)?}{
			$menu = '[<a href=\'./index.html\'>Index</a>]';
			$menu = '['.($i ? "<a href='$files[$i-1].html'>Prev</a>" :'Prev').'] | '.$menu ;
			$menu .= ' | ['.( ($i<$#files) ? "<a href='$files[$i+1].html'>Next</a>" : 'Next').']';
			'<p><small>'.$menu.( $1 ? ' | ' : '</small></p>');
		}seg;
		write_file($file, $body);
		
	}
	chdir '..';
}

chdir '../../..';

#####################
#### subroutines ####
#####################

sub doe_dir {
	my $dir = shift;
	my $sectie = shift || '';
	my $lib_bit = shift || 0;
	
	# scan for pods
	my %pods = pod_find({ -verbose => 0, -inc => 0 }, $dir);
	#print "debug: pods: \n", join("\n", keys %pods), "\n";

	make_dir('doc/html/'.$sectie);

	foreach my $pod (keys %pods) {

		# create dir
		$pod =~ s{^.*?$dir}{}; # strip base path
		unless ($lib_bit) {
			if ($pod =~ m{^(.*/)}) { make_dir('doc/html/'.$sectie.'/'.$1) }
		}
	
		# create html
		my $out_file = $pod;
		$out_file =~ s/(\.\w+)?$/.html/;
		if ($lib_bit) { $out_file =~ s|/|::|g }
			
		my @opt = (
			"--backlink=Top",
			#"--header",
			"--css=/docs.css",
			"--htmldir=doc/html/",
			"--podpath=$dir:lib",
			"--infile=$dir/$pod",
			"--outfile=doc/html/$sectie/$out_file",
			"--recurse",
			"--quiet",
		);
		unless ($pod =~ /index\.pod$/) { push @opt, "--index"}
		else { push @opt, "--noindex" }

		open SAVERR, '>&STDERR';
		open STDERR, '>/dev/null'; # pod2html trows all kind of warnings
		pod2html(@opt);
		open STDERR, '>&SAVERR';
	}
}

sub make_dir {
	my $dir = shift;
	my @dir = split /\/+/, $dir;
	$dir = '.';
	while (@dir) {
		$dir .= '/' . shift @dir;
		unless (-d $dir) { mkdir $dir || die $!	}
	}
}	

sub list_dir {
	my $dir = shift;
	$dir =~ s/\/?$/\//;
	opendir D, $dir;
	my @cont = readdir D;
	closedir D;
	@cont = grep {$_ !~ /^\.+$/} @cont;
	return map {$dir.$_} @cont;
}

sub get_file {
	my $file = shift;
	open IN, $file || die $!;
	my $body = join '', (<IN>);
	close IN;
	return $body;
}

sub write_file {
	my ($file, $body) = @_;
	open OUT, '>'.$file;
	print OUT $body;
	close OUT;
}

sub get_index {
	my $file = shift;
	my $body = get_file($file);
	$body =~ m/\Q<!-- INDEX BEGIN -->\E(.*?)\Q<!-- INDEX END -->\E/s || return '';
	$body = $1;
	$body =~ s{(href=['"]?)}{$1$file}g;
	return $body;
}

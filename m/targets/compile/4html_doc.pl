
# TODO -- doesn't seem to work !?

require 'm/Makefile.pm';
import Makefile qw/path_copy rmdir_force/;

my $make = Makefile->new;

unless ($make->{vars}{NO_HTML_DOC}) {exit 0;}

print "Generating user documentation in html.\n";

eval ( "use Pod::Tree::HTML;" );
if ($@) {
	print "==> You don't have  Pod::Tree::HTML -=- no html docs generated.\n";
	exit 0;
}

unless (-d 'b/doc') { mkdir 'b/doc' || die $!; }

my $items = doe_dir('', 'b/share/help/', 'b/doc');

open INDEX, ">b/doc/index.html" || die $! ;
print INDEX
'<html>
<head>
<title>Zoidberg</title>
<link rel="stylesheet" href="/zoid.css" type="text/css" />
</head>

<body BGCOLOR="#ffffff" TEXT="#000000">
<div align="left">

<p>This documentation was generated on '.localtime().'.</p>

<h1>Zoidberg user documentation</h1>

<p>Index of help files for using the Zoidberg shell,
while using the zoid this documentation is available by typing help or simply ?<br>
<br>
For more information see the Zoidberg Project
<a href="http://zoidberg.sourceforge.net">http://zoidberg.sourceforge.net</a>
</p>

'.gen_list($items).'

</div>
</body>

</html>';
close INDEX;

sub doe_dir {
	my ($rpath, $s_dir, $html_dir) = @_;
	my $dir = $s_dir.'/'.$rpath;
	my $items = {};

	# scan dir

	opendir FROM, $dir || die $!;
	my @files = grep {$_ !~ m/^\.\.?$/} readdir FROM;
	closedir FROM;

	# scan files
	$dir =~ s/\/?$/\//;
	foreach my $file (grep {(-f $dir.$_) && ($_ =~ /\.(pm|pod)$/i)} @files) {
		my $name = $file;
		$name =~ s/\.(pm|pod)$//i;
		my $new_file = $html_dir.'/'.$rpath.$name.".html";

		my $html = Pod::Tree::HTML->new( $dir.$file, $new_file);
		$html->set_options( 'title' => $name );
		$html->translate;

		$items->{$name} = $rpath.$name.".html";
	}

	# recurs through dirs
	foreach my $subdir (grep {-d $dir.$_} @files) {
		unless ($subdir eq 'CVS') {
			my $new_rpath = $rpath.$subdir;
			$new_rpath =~ s/\/?$/\//;
			my $new_dir = $html_dir.'/'.$new_rpath;
			unless (-e $new_dir) { mkdir $new_dir; }
			$items->{$subdir} = doe_dir($new_rpath, $s_dir, $html_dir); #recurs
		}
	}
	return $items
}

sub gen_list {
	my $ref = shift;
	my $l = shift || 0;
	my $body = ("\t"x$l)."<ul>\n";
	foreach my $key (sort grep {!ref($ref->{$_})} keys %{$ref}) {
		$body .= ("\t"x$l)."\t<li><a href=\"$ref->{$key}\">$key</a></li>\n";
	}
	foreach my $key (sort grep {ref($ref->{$_}) eq 'HASH'} keys %{$ref}) {
		$body .= ("\t"x$l)."\t<li><b>$key/</b></li>\n";
		$body .= gen_list($ref->{$key}, $l+1); # recurs
	}
	$body .= ("\t"x$l)."</ul>\n";
	return $body;
}


__END__

=head1 NAME

compile docs

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

Zoidberg specific (?)

generates html user documentation by using Pod::Tree::HTML

Doesn't work yet.

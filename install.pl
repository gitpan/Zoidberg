#!/usr/bin/perl

##################################################################
# Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.    #
# This program is free software; you can redistribute it and/or  #
# modify it under the same terms as Perl itself.                 #
#                                                                #
# This is the install script for the zoidberg program files.     #
# You'll also need the Zoidberg module.                          #
#                                                                #
# mailto:j.g.karssenberg@student.utwente.nl                      #
# http://zoidberg.sourceforge.net                                #
##################################################################

use strict;
use Getopt::Long qw(:config gnu_compat no_getopt_compat no_ignore_case);
use Pod::Usage;

##### default defaults #####
my $def_perl = '/usr/bin/perl';
my $def_prefix = '/usr/local/';
my $def_config = '/etc/';
my $log_file = 'zoid_install.log';
my $uninstall_file = 'uninstall.sh';
############################

my $help = 0;
my $silent = 0;
my $no_doc = 0;
my $message = "
This is the install script for the zoidberg program files.
These are useless without the Zoidberg modules.

See also <http://zoidberg.sourceforge.net>
";
GetOptions(
	'help|?|usage'	=> \$help,
	'silent'	=> \$silent,
	'no-doc'	=> \$no_doc,
	'prefix=s'	=> \$def_prefix,
	'config_dir=s'	=> \$def_config,
	'perl=s'	=> \$def_perl,
	'log_file=s'	=> \$log_file,
) || pod2usage( {
	'-message' => $message,
	'-exitval' => 1,
	'-verbose' => 0,
} );

if ($help) {
	pod2usage( {
		'-message' => $message,
		'-exitval' => 0,
		'-verbose' => 1,
	} );
}

unless ($no_doc) { 
	eval ( "use Pod::Tree::HTML;" );
	if ($@) { die "Module Pod::Tree::HTML not found in \@INC -- You might wanna use the \'--no-doc\' option"; }
}

$def_prefix =~ s/\/?$//; #/
$def_config =~ s/\/?$//; #/

open LOG, ">$log_file" || die "could not open log file - do you have permissions for the current directory?";
open UNI, ">$uninstall_file" || die "could not open uninstall file - do you have permissions for the current directory?";
print UNI << "EOH"
#!/bin/sh
################################################################
# This is the uninstall script for the zoidberg program files. #
# This script was autogenerated by the install.pl script       #
#                                                              #
# mailto:j.g.karssenberg\@student.utwente.nl                    #
# http://zoidberg.sourceforge.net                              #
################################################################
EOH
;

print "Installing Zoidberg shell...\n";

# get shebang
unless ($silent) { print "First of all we need to know where your perl binary is.\n"; }
my $perl = ask("Where is your perl installed?", $def_perl);
my $shebang = '#!'.$perl;
print LOG "Shebang is \'$shebang\'\n";

# get prefix
unless ($silent) { print "Next we need a prefix for \'bin/zoid\' and \'share/zoid/\' files.\n"; }
my $prefix = ask("Where would you like to install the zoid?", $def_prefix);
$prefix =~ s/\/?$//; #/
print LOG "Prefix is \"$prefix\"\n";

# get config dir
unless ($silent) { print "And last we need a place to store the (default) config files.\n"; }
my $config = ask("Where would you like to config files?", $def_config);
$config =~ s/\/?$//; #/
print LOG "Config in \"$config\"\n";

# some checks
unless (-e $perl && -x $perl) {
	unless ($silent) {
		print "## WARNING: the perl binary you specified \"$perl\" does not exist or is not executable.\n";
		my $ding = ask("Press \'f\' to continu anyway", "do not continu");
		unless ($ding eq 'f') {
			print LOG "Installation cancelled";
			die "Installation cancelled";
		}
	}
	else { die "No executable found at \"$perl\""; }
}
for ($prefix.'/bin', $prefix.'/share', $config) {
	unless (-e $_) { die "No such directory $_ -- please create it first"; }
}

# bin
print "Copying ./bin/fluff to $prefix/bin/zoid\n";
open IN, './bin/fluff' || "die Could not open file ./bin/fluff to read";
open OUT, '>'.$prefix.'/bin/zoid'  || "die Could not open file to $prefix/bin/zoid write";
print LOG "Created $prefix/bin/zoid\n";
print UNI "rm -f $prefix/bin/zoid &&\necho \"removed $prefix/bin/zoid\" ;\n";
while (<IN>) {
	s/^\#\!\/usr\/bin\/perl/$shebang/;
	s/^(my\s\$prefix\s=\s)\'\/usr\/local\/\'/$1\'$prefix\/\'/;
	s/^(my\s\$skel_dir\s=\s)\'\/etc\/zoid\/\'/$1\'$config\/zoid\/\'/; #/
	print OUT $_;
}
close OUT;
close IN;

chmod(0755, $prefix."/bin/zoid");

# etc
dircopy('./etc/', $config.'/zoid/');

# share
dircopy('./share/', $prefix.'/share/zoid/');

# html doc
unless ($no_doc) { make_doc($prefix.'/share/doc/zoid') }

my $slink = ask("Would you like to create the symlink $prefix/bin/zoidberg?", "y/N");
unless ($slink =~ /n/i) {
	symlink $prefix.'/bin/zoid', $prefix.'/bin/zoidberg';
	print LOG "Created $prefix/bin/zoidberg\n";
	print UNI "rm -f $prefix/bin/zoidberg &&\necho \"removed $prefix/bin/zoidberg\" ;\n";
}

print LOG "Done - all seems well\n";
close LOG;
close UNI;
print "Done.\tInstall log in \"$log_file\"\n$uninstall_file was created.\n## WARNING: do not forget to flush ~/.zoid if you update to a newer version\n";

unless ($silent) { # start the shell
	select(undef,undef,undef,0.8);
	print "Starting Zoidberg shell.\n";
	sleep 1;
	exec($prefix."/bin/zoid");
}

sub dircopy {
	# dir from, dir to
	my ($from, $to) = @_;
	$from =~ s/\/?$/\//;
	$to =~ s/\/?$/\//;
	print "Copying $from to $to\n";
	unless (-e $to) {
		mkdir($to) || die "Could not create dir $to";
		print LOG "Created dir ".$to."\n";
		print UNI "rm -fr ".$to." &&\necho \"removed ".$to."\" ;\n";
	}
	opendir FROM, $from || die "Could not open dir $from";
	my @files = readdir FROM;
	closedir FROM;
	shift @files; #.
	shift @files; #..
	foreach my $file (grep {-f $from.$_} @files) {
		open IN, $from.$file || die "Could not open file ".$from.$file." to read";
		open OUT, '>'.$to.$file  || die "Could not open file to ".$to.$file." write";
		print LOG "Created ".$to.$file."\n";
		print UNI "rm -f ".$to.$file." &&\necho \"removed ".$to.$file."\" ;\n";
		while (<IN>) { print OUT $_; }
		close OUT;
		close IN;
	}
	foreach my $dir (grep {(-d $from.$_)&&($_ ne 'CVS')} @files) {
		dircopy( $from.$dir, $to.$dir ); #recurs
	}
}

sub ask {
	my ($question, $default) = @_;
	my $answer = '';
	unless ($silent) {
		print "$question [$default] ";
		$answer = <>;
		chomp($answer);
	}
	return $answer ? $answer : $default;
}

sub make_doc {
	my $html_dir = shift;
	unless (-e $html_dir) {
		mkdir($html_dir) || die "Could not create dir $html_dir";
		print LOG "Created dir ".$html_dir."\n";
		print UNI "rm -fr ".$html_dir." &&\necho \"removed ".$html_dir."\" ;\n";
	}
	print "Generating user documentation in html.\n";

	my $s_dir = 'share/help/';
	my $items = doe_dir('', $s_dir, $html_dir);

	my $index_file = $html_dir."/index.html";
	open INDEX, ">$index_file" || die "Could not open file $index_file" ;
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

	print LOG "Created ".$index_file."\n";
	print UNI "rm -f ".$index_file." &&\necho \"removed ".$index_file."\" ;\n";
}

sub doe_dir {
	my ($rpath, $s_dir, $html_dir) = @_;
	my $dir = $s_dir.'/'.$rpath;
	my $items = {};

	# scan dir

	opendir FROM, $dir || die "Could not open dir $dir ";
	my @files = readdir FROM;
	closedir FROM;
	shift @files; #.
	shift @files; #..

	# scan files

	foreach my $file (grep {(-f $dir.$_) && ($_ =~ /\.(pm|pod)$/i)} @files) {
		my $name = $file;
		$name =~ s/\.\w+$//;
		my $new_file = $html_dir.'/'.$rpath.$name.".html";

		my $html = Pod::Tree::HTML->new( $dir.$file, $new_file);
		$html->set_options( 'title' => $name );
		$html->translate;

		print LOG "Created ".$new_file."\n";
		print UNI "rm -f ".$new_file." &&\necho \"removed ".$new_file."\" ;\n";

		$items->{$name} = $rpath.$name.".html";
	}

	# recurs through dirs

	foreach my $subdir (grep {-d $dir.$_} @files) {
		unless (grep {$_ eq $subdir} qw/CVS blib t/) {
			my $new_rpath = $rpath.$subdir;
			$new_rpath =~ s/\/?$/\//;
			my $new_dir = $html_dir.'/'.$new_rpath;
			unless (-e $new_dir) {
				mkdir $new_dir;
				print LOG "Created dir ".$new_dir."\n";
				print UNI "rm -fr ".$new_dir." &&\necho \"removed ".$new_dir."\" ;\n";
			}
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

    Install.pl -- an install script for the Zoidberg ProgramFiles

=head1 SYNOPSIS

    install.pl [options]

     Options:
       --help        Detailed help message
       --silent      Non-interactive mode
       --prefix      Set prefix
       --config_dir  Set config prefix
       --perl        Set location of the perl binary

=head1 OPTIONS

Abbreviations of options are also allowed.

=over 4

=item B<-h, --help>

    Print a this help message and exits.

=item B<-s, --silent>

    Non-interactive installation,
    a.k.a. "just use the default values".

=item B<--prefix>

    Set prefix, default is "/usr/local/".
    In this dir the subdirs "bin" and "share" are expected.
    Subdir "share/zoid" will be created. Unless --no-doc is
    used also subdir share/doc will be expected and subdir 
    share/doc/zoid created.

=item B<--config_dir>

    Set config prefix, default is "/etc/".
    Subdir "zoid" will be created,
    here the default config will be.

=item B<--perl>

    Set the location of the perl binary.
    Default is "/usr/bin/perl".

=item B<--log_file>

    Set the name for the log file.

=item B<--no-doc>

    Do not created html doc files. Html files will be
    put in $prefix/share/doc/zoid. The docs are always
    in pod format available in $prefix/share/zoid/help.

=back

=cut


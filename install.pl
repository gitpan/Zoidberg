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

my $silent = 0;
my $def_prefix = '/usr/local';
my $def_config = '/etc';

# commandline args
if (($ARGV[0] eq '-s')||($ARGV[0] eq '--silent')) {
	$silent = 1;
	if($ARGV[1]) { $def_prefix = $ARGV[1]; }
	if($ARGV[2]) { $def_config = $ARGV[2]; }
}
elsif (($ARGV[0] eq '-h')||($ARGV[0] eq '--help')||($ARGV[0] eq '-u')||($ARGV[0] eq '--usage')) {
	print "use: ".__FILE__." without options for an interactive install.\n";
	print "use: ".__FILE__." -s or --silent [\$prefix] [\$config_dir]\n";
	print "\tTo install non-interactively.\n";
	print "\tDefaults are: \$prefix=\'/usr/local\' and \$config_dir=\'/etc\'\n";
	exit;
}
elsif ($ARGV[0]) {
	print 'Unkown option try '.__FILE__." -h or --help .\n";
	exit;
}

$def_prefix =~ s/\/?$//; #/
$def_config =~ s/\/?$//; #/

open LOG, ">zoidberg_install.log" || die "could not open log file - do you have permissions for the current directory?";

print "Installing Zoidberg shell...\n";

# get prefix
my $prefix = '';
unless ($silent) {
	print "First we need a prefix for \'bin/zoid\' and \'share/zoid/\' files\n";
	print "Where would you like to install the zoid? [$def_prefix/] ";
	$prefix = <>;
	chomp($prefix);
}
unless ($prefix) { $prefix = $def_prefix; }
$prefix =~ s/\/?$//; #/
print LOG "Prefix is \"$prefix\"\n";

# get config dir
my $config = '';
unless ($silent) {
	print "Where would you like to config files? [$def_config/] ";
	$config = <>;
	chomp($config);
}
unless ($config) { $config = $def_config; }
$config =~ s/\/?$//; #/
print LOG "Config in \"$config\"\n";

# some checks
for ($prefix.'/bin', $prefix.'/share', $config) {
	unless (-e $_) { die "No such directory $_ -- please create it first"; }
}

# bin
print "Copying ./bin/fluff to $prefix/bin/zoid\n";
open IN, './bin/fluff' || "die Could not open file ./bin/fluff to read";
open OUT, '>'.$prefix.'/bin/zoid'  || "die Could not open file to $prefix/bin/zoid write";
print LOG "Created $prefix/bin/zoid\n";
while (<IN>) {
	s/\$prefix = \'\/usr\/local\/\'/\$prefix = \'$prefix\'/g;
	s/\$skel_dir = \'\/etc\/zoid\/\'/\$skel_dir = \'$config\/zoid\/\'/g; #/
	print OUT $_;
}
close OUT;
close IN;

# etc
dircopy('./etc/', $config.'/zoid/');

# share
dircopy('./share/', $prefix.'/share/zoid/');

chmod(0755, $prefix."/bin/zoid");

print LOG "Done - all seems well\n";
close LOG;
print "Done.\tInstall log in \"zoidberg_install.log\"\nwarning: do not forget to flush ~/.zoid if you update to a newer version\n";

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
	unless (-e $to) { mkdir($to) || die "Could not create dir $to"; }
	opendir FROM, $from || die "Could not open dir $from";
	my @files = readdir FROM;
	closedir FROM;
	shift @files; #.
	shift @files; #..
	foreach my $file (grep {-f $from.$_} @files) {
		open IN, $from.$file || die "Could not open file ".$from.$file." to read";
		open OUT, '>'.$to.$file  || die "Could not open file to ".$to.$file." write";
		print LOG "Created ".$to.$file."\n";
		while (<IN>) { print OUT $_; }
		close OUT;
		close IN;
	}
	foreach my $dir (grep {(-d $from.$_)&&($_ ne 'CVS')} @files) {
		dircopy( $from.$dir, $to.$dir ); #recurs
	}
}

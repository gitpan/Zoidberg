#!/usr/bin/perl

use strict;
use CPAN;

# TODO
# more choice to not compile all modules
# more intel in checking perl version number
# more intelligence in pinging CPAN

open LOG, ">zoidberg_install.log" || die "could not open log file - do you have permissions for the current directory?";

my $def_dir = '/usr/local/zoidberg';
my $d = "2>&1 >/dev/null";

sub printlog {
	print LOG shift(@_)."\t";
	if (shift @_) { print LOG "Ok"; }
	else { print LOG "Failed"; }
	print LOG "\n";
}

sub makefile {
	my $bit = system("perl Makefile.PL $d")?0:1 ;
	printlog( "perl Makefile.PL $d", $bit);
	return $bit;
}

sub make {
	my $bit = system("make $d")?0:1;
	printlog( "make $d", $bit);
	return $bit;
}

sub maketest {
	my $bit = system("make test $d")?0:1;
	printlog( "make test $d", $bit);
	return $bit;
}

sub makeinstall {
	my $bit = system("make install $d")?0:1;
	printlog( "make install $d", $bit);
	return $bit;
}

sub cpan {
	print LOG "Trying to install Devel::Symdump, Term::ReadKey, Term::ANSIScreen & Term::ANSIColor from CPAN\n";
	install "Devel::Symdump";
	install "Term::ReadKey" ;
	install "Term::ANSIScreen" ;
	install "Term::ANSIColor" ;
}

print "Installing Zoidberg shell...\n";

print "Where would you like to install the zoid? [$def_dir] ";
my $dir = <>;
chomp($dir);
unless ($dir) { $dir = $def_dir }
print LOG "Install dir is \"$dir\"\n";

print "Creating directory $dir\n";
unless (-d $dir) {
    my $bit = mkdir($dir);
    unless ($bit) {
    	print LOG "Could not mkdir $dir\n";
	close LOG;
    	die "Could not mkdir $dir - do you have permissions to do this?\n";
    }
}

chdir("Program Files");
for (['bin','executables'],['etc','configuration files'],['var','runtime data'],['share','data files']) {
    print "Installing $_->[1] into $dir/$_->[0]\n";
    print LOG "Installing $_->[1] into $dir/$_->[0]\n";
    mkdir("$dir/$_->[0]");
    system("cp -R $_->[0] \"$dir\"");
}
chmod(0755,"$dir/bin/fluff");
chdir("../");

print "Compiling and installing modules - this could take some time.\n";
makefile;
make;
unless (maketest) {
	print "Failed to compile modules - going to try CPAN\n";
	if (cpan) {
		unless (maketest) {
			print LOG "failed to compile modules, please read the README file\n";
			close LOG;
			die "failed to compile modules, please read the README file\n";
		}
	}
	else {
		print LOG "failed to compile modules, please read the README file\n";
		close LOG;
		die "failed to compile modules, please read the README file\n";
	}
}
unless (makeinstall) {
	print LOG "failed to install modules, Do you have the proper permissions?\n";
	close LOG;
	die "failed to install modules, Do you have the proper permissions?\n";
}

print "Do you wish to create the symlink /usr/bin/fluff? [Yn] ";
my $ans = <>;
unless ($ans =~ /n/i) {
    symlink("$dir/bin/fluff", "/usr/bin/fluff");
    print LOG "Created symlink /usr/bin/fluff to $dir/bin/fluff\n";
}
print "Do you wish to create the symlink /usr/bin/zoid? [Yn] ";
$ans = <>;
unless ($ans =~ /n/i) {
    symlink("$dir/bin/fluff", "/usr/bin/zoid");
    print LOG "Created symlink /usr/bin/zoid to $dir/bin/fluff\n";
}
print LOG "Done - all seems well\n";
close LOG;
print "Done.\tInstall log in \"zoidberg_install.log\"\n";
select(undef,undef,undef,0.8);
print "Starting Zoidberg shell.\n";
sleep 1;
exec($dir."/bin/fluff");


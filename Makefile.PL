use ExtUtils::MakeMaker;
use strict;

my $pms = {};
my $pods1 = {};
my $pods3 = {};
my $depends = {	# dependecies for scripts -- can't be distilled from .pm's
	'Getopt::Long'		=> '2.32',
	'Pod::Usage'		=> '1.14',
	#'Pod::Tree::HTML'	=> '1.08', # Pod/Tree/HTML.pm seems a bad boy
};

# read MANIFEST for .pm's
open MANIFEST, "< MANIFEST" || die "Couldn't open ./MANIFEST";
while(<MANIFEST>) {
	chomp;
	if ($_ !~ /.pm$/) { next; }
	my $dest = $_;

	### convert our <insert cursing> dir structure
	 my @dirs = split(/\//, $dest);
	 my $file = pop @dirs;
	 if(pop @dirs) { # lose last dir
		 unshift @dirs, 'Zoidberg';
	 }
	 $dest = join('/', @dirs).(@dirs ? '/' : '').$file;
	###

	my $podname = $dest;
	$dest = '$(INST_LIBDIR)/'.$dest;
	$pms->{$_} = $dest;

	# set right name for pod3
	$podname =~ s/\//\:\:/g;
	$podname =~ s/\.pm$//;
	$pods3->{$_} = '$(INST_MAN3DIR)/'.$podname.'.$(MAN3EXT)';
}
close(MANIFEST);

# set man1 pods
foreach (qw/zoid.pod/) { # this should come from MANIFEST also -- shouldn't it ?
	my $name = $_;
	$name =~ s/\.pod$//;
	$pods1->{$_} = '$(INST_MAN1DIR)/'.$name.'.$(MAN1EXT)';
}

# get dependecies from Depends.pd
open DEP, "< Depends.pd" || die "Couldn't open ./Depends.pd";
my $content = join("",(<DEP>));
close DEP;
my $VAR1;
eval($content);
if ($@) { die "Failed to eval the contents of ./Depends.pd ( $@ )"; }
for (keys %{$VAR1}) { $depends->{$_} = $VAR1->{$_}; }

WriteMakefile (
	'NAME'		=> 'Zoidberg',
	'VERSION_FROM'	=> 'Zoidberg.pm',
	'AUTHOR'	=> 'Jaap G Karssenberg <j.g.karssenberg@student.utwente.nl>',
	'ABSTRACT'	=> 'Zoidberg -- a modular perl shell',
#	'EXE_FILES'	=> [ qw(bin/zoid) ],
	'MAN1PODS'	=> $pods1,
	'MAN3PODS'	=> $pods3,
	'PM'		=> $pms,
#	'dist'		=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz' }
	'PREREQ_PM'	=> $depends,
);



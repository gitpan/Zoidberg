#!/usr/bin/perl

use CPAN ();
use Zoidberg::Shell;
use Zoidberg::Utils qw/getopt complain message/;

# initialise CPAN config
CPAN::Config->load;

# specify commandline options - see man Zoidberg::Utils::GetOpt
# ( the real cpan(1) command knows a lot more options )
$getopt = 'version,v help,h @';

($opts, $args) = eval { getopt($getopt, @ARGV) }; # parse commandline options
if ($@) {
	complain; # print a nice error message
        exit 1;   # return an error
}

# handle options
if ($$opts{help}) {
	print "This is just an example script, the code is the documentation.\n";
	exit;
}
elsif ($$opts{version}) {
	print $_.'.pm version '.${$_.'::VERSION'}."\n"
		for qw/Zoidberg::Shell CPAN/;
	exit;
}
elsif (@$args) { # handle arguments
	CPAN::Shell->install(@$args);
	exit;
}
# else start an interactive shell

# the mode string we need below
my $mode = 'CPAN::Shell->';

# create shell object -- see man Zoidberg::Shell
$shell = Zoidberg::Shell->new(
	# provide non-default settings
	settings => {
		# don't use zoid's rcfiles
		norc => 1,
		# set alternate history file
		Log => {
			logfile => $ENV{HOME}.'/.example_cpan.pl_history',
		},
		# redirect all commands to the CPAN::Shell class
		mode => $mode,
	},
	# set aliases for our cpan mode
	aliases => {
		'mode_'.$mode => {
			'?'    => 'h',     # normally '?' would be considered a glob
			'q'    => 'quit',  # alias to an alias
			'quit' => '!exit', # '!exit' is 'exit' in the default mode
		},
	},
);

# use a custom prompt,
# hope you have Term::ReadLine::Zoid and Env::PS1
$ENV{PS1} = '\C{green}cpan>\C{reset} ';
$ENV{PS2} = '\C{green}    >\C{reset} ';

# message only printed when interactive -- see man Zoidberg::Utils::Output
message "--[ This is a Zoidberg wrapper for CPAN.pm ]--
## This script is only an example, it is not intende for real usage
## Commands prefixed with a '!' will be handled by zoid";

$shell->main_loop(); # run interative prompt

message '--[ Have a nice day ! ]--'; 

$shell->round_up(); # let all objects clean up after themselfs

__END__

=head1 NAME

cpan.pl - example shell application

=head1 DESCRIPTION

This script demonstrates how to wrap a module like CPAN.pm
with a custom Zoidberg shell. The code is the documentation.

B<This script is for the sake of demonstration only>;
if you want to use CPAN from within a Zoidberg shell use the
CPAN plugin, which provides better tab completion. To enter
the cpan shell from zoid type: C<mode cpan>.

=head1 AUTHOR

Jaap Karssenberg, E<lt>pardus@cpan.orgE<gt>


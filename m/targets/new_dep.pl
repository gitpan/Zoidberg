
require 'm/Makefile.pm';
import Makefile qw/get_version pd_write/;

my $make = Makefile->new;

my $prereq = {};
my $packages = [];

for (grep m/^(\.\/)?(lib\/.*\.(?i:pm)|bin\/.*)$/, $make->manifest) {
	print "Scanning $_ \n";
	open IN, $_ || die $!;
	while (<IN>) {
        /^__END__/ && last;
		if ($_ =~ /^\s*use\s+(?:base\s*)?['"]?(.*?)['"]?[;\s\n]/) {
			my $mod = $1;
			unless (($mod eq 'strict') || ($mod =~ /^Zoidberg(\:\:|$)/)) {
				if (my $version = get_version($mod)) {
					unless ($version eq '-1, set by base.pm') { # !??
						$prereq->{$mod} = $version;
					}
				}
			}
		}
		elsif ($_ =~ /^\s*package\s+['"]?(Zoidberg.*?)[;\s\n]/) { push @{$packages}, $1; }
		if ($_ =~ /^\s*__END__\s*$/) { last; }
	};
	close IN;
}

pd_write('m/Depends.pd', $prereq) && print "Wrote ./m/Depends.pd\n";


my $body = "use Test::More tests => ".($#{$packages} + 1).";\n";
$body .= join( "\n", map {"use_ok(\'$_\');"} sort @{$packages})."\n";
open TEST, ">t/use_ok.t" || die "could not open ./t/use_ok.t for writing";
print TEST $body;
close TEST;

print "Wrote ./t/use_ok.t\n";

print "Run perl Makefile.PL again to update dependencies in the Makefile.\n";


__END__

=head1 NAME

new dep

=head1 DESCRIPTION

This script is ment as a make target in combination with the
Makefile.pm module. See module documentation for more details.

=head1 FUNCTION

Zoidberg specific (?)

creates F<Depends.pd> and F<t/use_ok.t> based on the current system. 

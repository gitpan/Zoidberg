
require 'm/Makefile.pm';
import Makefile qw/pd_read/;

my $make = Makefile->new;

my $packages = pd_read('m/use_ok.pd');
my @packages = (@{$packages->{core}}, @{$packages->{$make->{profile}}});

my $body = "use Test::More tests => ".($#packages + 1).";\n";
$body .= join( "\n", map {"use_ok(\'$_\');"} sort @packages)."\n";

unless (-e 'b/t/') { mkdir 'b/t' }
open TEST, '>b/t/00_use_ok.t' || die "could not open ./b/t/use_ok.t for writing";
print TEST $body;
close TEST || die "could not open ./b/t/use_ok.t for writing";

print "Created a t/00_use_ok.t file\n";

# create test executable using the make defined PERL
open BIN, '>b/t/echo' || die "could not open ./b/t/echo for writing";
print BIN '#!', $make->{vars}{PERL}, "\n", 'print join(q/ /, @ARGV), "\n";', "\n";
close BIN || die "could not open ./b/t/echo for writing";
chmod 0755, 'b/t/echo';

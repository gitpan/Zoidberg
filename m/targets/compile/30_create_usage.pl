
use Pod::Text;
my $parser = Pod::Text->new();

# Parse complete man page to temp file
$parser->parse_from_file('./man1/zoid.pod', 'b/zoid.usage~~'); 

# append required sections to bin/zoid
my @sections = qw/synopsis options bugs/;

open TEXT, 'b/zoid.usage~~' || die $!;
open FLUFF, '>>b/bin/zoid' || die $!;

my $write = 0;
while (<TEXT>) {
	if (/^([A-Z]+)/) {
		if (grep {$1 eq uc($_)} @sections) { $write = 1 }
		else { $write = 0 }
	}
	
	if ($write) { 
		s/\*(\w+)\*/$1/g;
		print FLUFF $_;
	}
}

close TEXT;
close FLUFF;

__END__

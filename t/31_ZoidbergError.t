use Test::More tests => 3;
use Zoidberg::Utils::Error;

# normal use

eval { error( 'dusss' ) };

my $error = {
	'file' => 'b/t/31_ZoidbergError.t',
	'string' => 'dusss',
	'package' => 'main',
	'line' => 6 ,
};

#use Data::Dumper;
#print Dumper $@;

is_deeply( $@, $error, 'basic exception');

# overloaded use

eval { error( { test => [qw/1 2 3/] }, 'test failed' ) };

$error = {
	'file' => 'b/t/31_ZoidbergError.t',
	'string' => 'test failed',
	'package' => 'main',
	'line' => 22,
	'test' => [ 1, 2, 3 ],
};

is_deeply( $@, $error, 'overloaded use');

# bug use

eval { bug( 'dit is een bug' ) };

$error = {
	'file' => 'b/t/31_ZoidbergError.t',
	'string' => 'dit is een bug',
	'package' => 'main',
	'line' => 36 ,
	'is_bug' => 1,
};

is_deeply( $@, $error, 'bug reporting');

use Test::More tests => 19;
use Zoidberg::StringParser;

my $simple_gram = {
	esc => '\\',
	tokens => { '|' => 'PIPE' },
	nests => {
		'{' => '}',
	},
	quotes => { 
		'"' => '"',
		'\'' => '\'',
	},
};

my $array_gram = {
	esc => '\\',
	tokens => [ 
		[ qr/\|/,  'PIPE' ],
		[ qr/\s+/, '_CUT' ],
	],
	quotes => {
                '"' => '"',
                '\'' => '\'',
        },
	meta => sub {
		my ($self, $block) = @_;
		return undef unless length($block);
		return $block;
	},
};

my $parser = Zoidberg::StringParser->new({}, {simple => $simple_gram, array => $array_gram });

$parser->set('');
my @r = $parser->get;
ok(!defined($r[0]), 'empty get' ); # 1

$parser->set('simple', 'dit is een "quoted | pipe" | dit niet');

is_deeply([$parser->get], ['dit is een "quoted | pipe" ', 'PIPE'], 'simple get'); # 2
is_deeply([$parser->get], [' dit niet'], 'another get'); # 3

$parser->set('simple', 0);
is_deeply([$parser->get], ['0'], 'null value'); # 4

for (
	[
		['simple', 'just { checking { how |  this } works | for } | you :)'],
		['just { checking { how |  this } works | for } ', 'PIPE'],
		'nested nests'
	], # 5
	[
		['simple', 'dit was { een bug " } " in | de } | vorige versie'],
		['dit was { een bug " } " in | de } ', 'PIPE'],
		'quoted nests'
	], # 6
	[
		['simple', 'hier open " ik dus qquotes', sub { return ' die ik hier " sluit | ja' }],
		['hier open " ik dus qquotes die ik hier " sluit ', 'PIPE'],
		'pull mechanism'
	], # 7
) {
	$parser->set( @{$_->[0]} );
	is_deeply([$parser->get], $_->[1], $_->[2]);
}

my @blocks = $parser->split('simple', 'ls -al | grep -v CVS | xargs grep "dus | ja" | rm -fr');
my @i_want = (\'ls -al ', 'PIPE', \' grep -v CVS ', 'PIPE', \' xargs grep "dus | ja" ', 'PIPE', \' rm -fr');
is_deeply(\@blocks, \@i_want, 'basic split'); # 8

for (
	[
		['simple', 'dit is line 1 | grep 1', 'dit is alweer | de volgende line'],
		[\'dit is line 1 ', 'PIPE', \' grep 1'],
		'basic getline'
	],
	[
		['simple', sub { return 'dit is line 1 | grep 1' }, sub { die "WTF !?\n" }],
		[\'dit is line 1 ', 'PIPE', \' grep 1'],
		'getline with subs'
	],
	[
		['array', 'dit is dus | ook "zoiets ja"'],
		[map( {\$_} qw/dit is dus/), 'PIPE', \'ook', \'"zoiets ja"'],
		'advanced getline with array gram'
	],
	[
		['simple', 'dit is een escaped \| pipe, en dit een escape \\\\ dus, "dit \\\\ trouwens ook"'],
		[\'dit is een escaped | pipe, en dit een escape \\ dus, "dit \\ trouwens ook"'],
		'escape removal and escaping'
	],
) {
	@blocks = $parser->getline( @{$_->[0]} );
	#use Data::Dumper;
	#print Dumper \@blocks;
	is_deeply(\@blocks, $_->[1], $_->[2]); # 9 10 11 12
}

# test caching

ok(
	$simple_gram->{_prepared} && ref($simple_gram->{quotes}) eq 'Zoidberg::StringParser::hash',
	'grammars are cached' ); # 13

# test error

$parser->split('simple', 'some broken { syntax');
ok( $parser->error eq 'Unmatched nest at end of input: {', 'error function works' ); # 14
#print 'error -->', $parser->error, "<--\n";

$parser->split(['simple', {no_esc_rm=>1}], 'some broken { syntax');
ok( $parser->error eq 'Unmatched nest at end of input: {', 'error function works with no_esc_rm' ); # 15
#print 'error -->', $parser->error, "<--\n";

# test synopsis - just be sure

my $base_gram = {
    esc => '\\',
    quotes => {
        q{"} => q{"},
        q{'} => q{'},
    },
};

$parser = Zoidberg::StringParser->new($base_gram);
@blocks = $parser->split(qr/\|/, qq{ls -al | cat > "somefile with a pipe | in it"} );
@i_want = ('ls -al ', ' cat > "somefile with a pipe | in it"');
is_deeply(\@blocks, \@i_want, 'base gram works'); # 16

# testing settings

$parser = Zoidberg::StringParser->new($base_gram, {}, { no_split_intel => 1 });
@blocks = $parser->split(qr/\|/, qq{ls -al | cat > "somefile with a pipe | in it"} );
@i_want = (\'ls -al ', \' cat > "somefile with a pipe | in it"');
is_deeply(\@blocks, \@i_want, 'no_split_intel setting works'); # 17

$parser = Zoidberg::StringParser->new({}, { simple => $simple_gram }, { allow_broken => 1 });
@blocks = $parser->getline('simple', 'some  { syntax ', 'and } more');
ok( ! $parser->error && scalar(@blocks) == 1 , 'allow_broken works' ); # 18

$parser = Zoidberg::StringParser->new({}, { simple => $simple_gram }, { raise_error => 1 });
eval { $parser->split('simple', 'some broken { syntax') };
ok( $@ eq "Unmatched nest at end of input: {\n", 'raise_error works'); # 19

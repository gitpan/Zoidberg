
use Zoidberg::Config;
use Zoidberg::StringParse;

require Test::More;

my @test_data1 = (
	[
		qq/ls -al | dus\n/,
		[\'ls -al ', \" dus\n"],
		'simple pipeline 1'
	],
	[
		qq/ls -al | grep dus | xargs dus\n/,
		[\'ls -al ', \' grep dus ', \" xargs dus\n"],
		'simple pipeline 2'
	],
	[
		q/ # | $ | @ | ! | % | ^ | * /,
		[map {\" $_ "} '#', qw/$ @ ! % ^ */],
		'some non word chars'
	],
	[
		qq/cd .. && for (glob('*')) { print '> '.\$_ }\n/,
		[\'cd .. ', 'AND', \" for (glob('*')) { print '> '.\$_ }\n"],
		'simple logic and'
	],
	[
		qq{ls .. || ls /\n},
		[\'ls .. ', 'OR', \" ls /\n"],
		'simple logic or'
	],
	[
		 qq#ls .. || ls / ; cd .. && for (glob('*')) { print '> '.\$_ }\n#,
		 [\'ls .. ', 'OR', \" ls / ", 'EOS', \' cd .. ', 'AND', \" for (glob('*')) { print '> '.\$_ }\n"],
		'logic list 1'
	],
	[
		qq#cd .. | dus || cd / || cat error.txt | bieper\n#,
		[\'cd .. ', \' dus ', 'OR', \' cd / ', 'OR', \' cat error.txt ', \" bieper\n"],
		'logic list 2'
	],
	# TODO more test data
);

my @test_data2 = (
	[
		qq#ls -al ../dus \n#,
		[qw#ls -al ../dus#],
		'simple statement'
	],
	[
		qq#ls -al "./ dus  " ../hmm\n#,
		[qw/ls -al/, '"./ dus  "', '../hmm'],
		'another statement'
	],
	[
		q#alias du=du\ -k#,
		['alias', 'du=du\ -k'],
		'escape whitespace'
	],
);

import Test::More tests => scalar(@test_data1) + scalar(@test_data2) + 1;

my $collection = Zoidberg::Config::readfile('./share/skel/grammar.pd');
my $parser = Zoidberg::StringParse->new($collection->{_base_gram}, $collection);

print "# script grammar\n";

for my $data (@test_data1) {
	my @blocks = $parser->split('script_gram', $data->[0]);
	is_deeply(\@blocks, $data->[1], $data->[2]);
}

print "# word grammar\n";

for my $data (@test_data2) {
        my @blocks = $parser->split('word_gram', $data->[0]);
        is_deeply(\@blocks, $data->[1], $data->[2]);
}

print "# rest\n";

my @blocks = $parser->split(qr/XXX/, qq{ ff die XXX base_gram "XXX" XXX shit \\XXX testen} );
my @i_want = (' ff die ', ' base_gram "XXX" ', ' shit \\XXX testen');
is_deeply(\@blocks, \@i_want, 'base_gram works');


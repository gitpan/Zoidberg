
use Zoidberg::Shell qw/AUTOLOAD/;

$VAR1 = {
	module => 'Zoidberg::Fish::ReadLine',
	events => {
		readline => 'wrap_rl',
		readmore => 'wrap_rl_more',
	},
}

{
	module => 'Zoidberg::Fish::Log',
	config => {
		loghist  => 1, # if false new commands are ignored
		logfile  => '~/.history.yaml',
		maxlines => 150,
		no_duplicates => 1,
	},
	import => [qw/read_history/],
	# TODO export => [qw/fc history/]
};

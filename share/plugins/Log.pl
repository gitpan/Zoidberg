{
	module => 'Zoidberg::Fish::Log',
	config => {
		loghist  => 1, # if false new commands are ignored
		logfile  => '~/.history.yaml',
		maxlines => 128,
		no_duplicates => 1,
	},
	export => [qw/fc history log/],
};

{
	module => 'Zoidberg::Fish::Log',
	config => {
		loghist  => 1, # if false new commands are ignored
		logfile  => '~/.zoid.log.yaml',
		maxlines => 128,
		no_duplicates => 1,
		keep => { pwd => 10 },
	},
	export => [qw/fc history log/],
};

{
	module => 'Zoidberg::Fish::Commands',
	config => { max_dir_hist => 10 },
	load_on_init => 1, # allready using AutoLoader
	commands => {
			back      => 'cd(q/<-/)',
			forw      => 'cd(q/->/)',
	},
	export => [qw/
		cd		exec		eval
		command		false		fc
		getopts		newgrp		pwd
		read		true		umask
		wait		set 		export
		_delete_object	_load_object	_hide
		_unhide		source
		alias		unalias		
		setenv		unsetenv

		dirs		popd		pushd
		help

		fg bg kill jobs
	/],
}

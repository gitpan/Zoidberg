{
	module  => 'Zoidberg::Fish::Commands',
	config  => {
		max_dir_hist => 10
	},
	events  => { loadrc => 'plug' }, # allready using AutoLoader
	aliases => {
		back => 'cd(q/-1/)',
		forw => 'cd(q/+1/)',
	},
	export  => [qw/
		cd pwd
		exec eval source
		true false
		newgrp umask
		read
		wait fg bg kill jobs
		set export setenv unsetenv alias unalias
		dirs popd pushd
		symbols which help
	/],
}

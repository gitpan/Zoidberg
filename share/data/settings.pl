{
	output => {
		warning => 'yellow',
		error => 'red',
		debug => 'green',
		'sql-data' => 'yellow',
	},
	clothes => {
		keys => [qw/settings vars error commands aliases events/],
		subs => [qw/shell alias unalias setting set source/],
	},
	perl_keywords => [qw/
		if unless for foreach while until 
		print
		push shift unshift pop splice
		delete
		do eval
		tie untie
		my our use no sub 
		import bless
	/],
	naked_zoid => 0,
	cache_time => 300, # time in seconds -- 5min
	hide_private_method => 1,
	hide_hidden_files => 1,
};

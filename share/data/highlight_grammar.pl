
# perl functions copied from perlfunc (perl version 5.8)
'perl_functions' => [qw/
	abs accept alarm atan2
	bind binmode bless
	caller chdir chmod chomp chop chown chr chroot close closedir connect continue cos crypt
	dbmclose dbmopen defined delete die do dump
	each endgrent endhostent endnetent endprotoent endpwent endservent eof eval exec exists exit exp
	fcntl fileno flock fork format formline
	getc getgrent getgrgid getgrnam gethostbyaddr gethostbyname gethostent getlogin getnetbyaddr 
	getnetbyname getnetent getpeername getpgrp getppid getpriority getprotobyname getprotobynumber 
	getprotoent getpwent getpwnam getpwuid getservbyname getservbyport getservent getsockname getsockopt glob gmtime goto grep
	hex
	import index int ioctl
	join
	keys kill
	last lc lcfirst length link listen local localtime lock log lstat
	m map mkdir msgctl msgget msgrcv msgsnd my
	next no
	oct open opendir ord our
	pack package pipe pop pos print printf prototype push
	q qq qr quotemeta qw qx
	rand read readdir readline readlink readpipe recv redo ref rename require reset return reverse rewinddir rindex rmdir
	s scalar seek seekdir select semctl semget semop send setgrent sethostent setnetent setpgrp setpriority setprotoent setpwent 
	setservent setsockopt shift shmctl shmget shmread shmwrite shutdown sin sleep socket socketpair sort splice split sprintf 
	sqrt srand stat study sub substr symlink syscall sysopen sysread sysseek system syswrite
	tell telldir tie tied time times tr truncate
	uc ucfirst umask undef unlink unpack unshift untie use utime
	values vec
	wait waitpid wantarray warn write
	y
/];
$VAR1 = {
		'PERL' => {
			'nests' => [
				['\"', '\"', 'yellow'],
				['\'', '\'', 'yellow'],
			],
			'limits' => [';', '\s+', '/', '\)', '\(', '\{', '\}', '\[', '\]'],
			'escape' => '\\\\', #'
			'rules' => [
				['^[\$\@\%]', 'green'],
			],
			'colors' => {
				'cyan' => [qw/my our local sub/],
				'red' => [qw/__END__ __DATA__ __FILE__ __PACKAGE__ __LINE__ \\WINC \\W?ISA \\WARGV STDIN STDOUT STDERR DESTROY/],
			},
		},
		'SQL' => {
			'nests' => [
				['\"', '\"', 'yellow'],
				['\'', '\'', 'yellow'],
			],
			'limits' => [';', '\s+', '/', '\)', '\(', '\{', '\}', '\[', '\]'],
			'escape' => '\\\\', #'
			'rules' => [],
			'colors' => {
				'green' => [qw/?i:select insert update descibe drop alter delete show use create grant/],
				'red' => [qw/?i:from where order group like by asc desc all privileges identified/],
			},
		},
		'NOTE' => { 'default_color' => 'yellow', },
        'C' => {
            'default_color' => 'on_red',
        },
	},
};
# for highlighting
$VAR1->{syntax}{PERL}{colors}{underline} = $VAR1->{perl_functions};

$VAR1;
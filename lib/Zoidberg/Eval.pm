package Zoidberg::Eval;

use Data::Dumper;
use Zoidberg::FileRoutines qw/:exec_scope/;

$| = 1;

sub _New {
	my $class = shift;
	my $self = {};
	$self->{zoid} = shift; # this will be $self for eval blocks
	bless $self, $class;
}

sub _Eval_block {
	my $_Eval = shift;
	my ($_String,$_Context,$_Opts) = @_;

	my $self = $_Eval->{zoid}; # $self ain't always what it appears to be
	$self->print("Zoidberg::Eval->_Eval_block('".join("', '", @_[0..2])."')",'debug');
	my $_Code = q|$self->print("Could not found a parser for \"$context\"", 'error');|;
	my @_Bits = (0,0,1);
	my @_Args = ();
	# Bits: not_interpolate_pound, not_parse_opts, do_command_syntax
	if (ref($self->{grammar}{context}{$_Context}) && $self->{grammar}{context}{$_Context}[0]) {
		my $sub = $self->{grammar}{context}{$_Context}[0];
		if (ref($self->{grammar}{context}{$_Context}[2])) { @_Bits = @{$self->{grammar}{context}{$_Context}[2]}; }
		$sub =~ s/^->//;
		if ($sub =~ s/(\(.*\))\s*$//) { @_Args = eval($1); }
		if ($_Bits[2]) {
			if ($_Bits[1]) { $_Code = qq|\$self->$sub([\@_Args], \$_Opts);| }
			else { $_Code = qq|\$self->$sub(\@_Args);| }
		}
		else { $_Code = qq|\$self->$sub(\@_Args, \$_String|.($_Bits[1] ? q|, \$_Opts);| : ');') }
	}
	elsif (($_Context eq 'PERL')||($_Context eq 'ZOID')) {
		$_Code = $_Eval->_perlify($_String);
		if ($_Context eq 'PERL') { $_Code = 'no strict; '.$_Code; } # TODO make configable
		@_Bits = (1,0,0);
	}
	elsif ($_Context eq 'SYSTEM') {
		$_Code = q|$_Eval->_system(@_Args)|;
		@_Bits = (0,1,1);
	}

	if ($_Bits[2]) { # command syntax
		unless ($_Bits[0]) { push @_Args, map {$_Eval->_interpolate($_)} $_Eval->_parse_command($_String); }
		else { push @_Args, $_Eval->_parse_command($_String); }
	}
	elsif (!$_Bits[0]) { $_Code = $_Eval->_interpolate($_Code); }

	unless ($_Bits[1]) { $_Code = $_Eval->_parse_opts($_Code, $_Opts); }
	$self->print("Going to eval '$_Code'", "debug");

	$Zoidberg::Eval::Self = $_Eval; # Hack alert

	$_ = $self->{_};
	my $_Re = [eval($_Code)];
	$self->{_} = $_;

	if ($_Context eq 'PERL') { print "\n"; } # ranzige hack

	if ($@) {
		$self->{exec_error} = 1;
        my $er = $@;chomp$er;
		$self->print("bwuububu buu: '$er'", 'error');
	}


	unless (@{$_Re}) { $_Re = [undef]; } # just to be sure there is a @{$_Re}[-1]
	return $_Re;
}

sub _parse_command { # parse sh like syntax to array args
	my $self = shift;
	my $string = shift;
	$string =~ s/\A\s*//gm ; # TODO deze regex in stringparse
	my @args = map {$_->[0]} @{$self->{zoid}->{StringParser}->parse($string,'space_gram')};
	while ($args[-1] eq '') { pop @args; } # ranzige hack
	$self->{zoid}->print("Command args: '".join("', '", @args)."'", 'debug');
	return @args;
}

sub _perlify { # fully qualify -> and pound syntax
	my $self = shift;
	my $string = shift;
	my $tree = $self->{zoid}{StringParser}->parse($string,'eval_zoid_gram');
	#print "debug ".Dumper($tree);
	foreach my $ref (@{$tree}) {
		if ($ref->[1] eq "\xA3_") { $ref->[1] = '$self->{_}'}
		elsif ($ref->[1] =~ s/^(->|\xA3)//) {
			if ($self->{zoid}{core}{show_naked_zoid} && ($1 ne "\xA3")) { $ref->[1] = '$self->'.$ref->[1]; }
			elsif (grep {$_ eq $ref->[1]} @{$self->{zoid}->list_clothes}) { $ref->[1]='$self->'.$ref->[1]; }
			elsif ($ref->[1] =~ m|^\{(\w+)\}$|) { $ref->[1] = '$self->{vars}'.$ref->[1]; }
			else { $ref->[1] = '$self->objects(\''.$ref->[1].'\')' }
		}
	}
	$string = join('', map {$_->[0].$_->[1]} @{$tree});
	return $string;
}

sub _interpolate { # substitutes pound vars with their values
	# TODO fine tuning and grinding
	my $self = shift;
	my $string = shift;
	#if ($string =~ /^(\$|\xA3)_$/) { $string = \$self->{zoid}{_}; }
	#else {
		my $tree = $self->{zoid}{StringParser}->parse($string,'eval_zoid_gram');
		#print "debug ".Dumper($tree);
		foreach my $ref (@{$tree}) {
			if ($ref->[1] eq "\xA3_") { $ref->[1] = $self->{zoid}{_}}
			elsif ($ref->[1] =~ s/^(->|\xA3)//) { # Vunzige implementatie -- moet via stringparse strakker
				if ($self->{zoid}{core}{show_naked_zoid} && ($1 ne "\xA3")) { $ref->[1] = eval('$self->{zoid}->'.$ref->[1]); }
				elsif (grep {$_ eq $ref->[1]} @{$self->{zoid}->list_clothes}) { $ref->[1] = eval('$self->{zoid}->'.$ref->[1]); }
				elsif ($ref->[1] =~ m|^\{(\w+)\}$|) { $ref->[1] = eval('$self->{zoid}{vars}->'.$ref->[1]); }
				else { $ref->[1] = eval('$self->{zoid}->objects(\''.$ref->[1].'\')') }
			}
		}
		$string = join('', map {$_->[0].$_->[1]} @{$tree});
	#}
	return $string;
}

sub _parse_opts { # parse options switches
	my $self = shift;
	my ($string, $opts) = @_;

	# TODO if in pipeline set 'n' as defult unless 'N'

	if ($opts =~ m/g/) { $string = "\nwhile (<STDIN>) {\n\tif (eval {".$string."}) { print \$_; }\n}"; }
	elsif ($opts =~ m/p/) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n\tprint \$_\n}"; }
	elsif ($opts =~ m/n/) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n}"; }

	if ($opts =~ m/b(\d+)/) {
		$string = qq{ \$self->print(
	Benchmark::timestr(Benchmark::timethis($1, sub{
		$string
	},'','none'))) };
	}

	return $string;
}

sub _system {
	my $self = shift;
	my @r = ();
	for (@_) { push @r, map {s/\\//g; $_} (/[^\w\/\.\-\=]/) ? @{$self->{zoid}->Intel->expand_files($_)} : ($_) ; }
	if (is_executable($r[0])) {
		$self->{zoid}{_} = $r[-1]; # useless in fork (?)
		if ($self->{zoid}->{round_up}) { system(@r); }
		else { exec {$r[0]} @r; }
	}
	else { $self->{zoid}->print("No such executable \"$r[0]\"", 'error'); }

}

sub AUTOLOAD {
	## Code inspired by Shell.pm -- but rewrote it

	if (ref($_[0]) eq 'Zoidberg::Eval') { shift; }
	my $self = $Zoidberg::Eval::Self ; # hack alert

	my $cmd = (split/::/,$AUTOLOAD)[-1];

	if (is_executable($cmd)) { # system
		local(*SAVEOUT, *READ, *WRITE);
		open SAVEOUT, '>&STDOUT';
		pipe READ, WRITE;
		open STDOUT, '>&WRITE';
		close WRITE;
		my $pid = system($cmd,@_);
		open STDOUT, '>&SAVEOUT';
		close SAVEOUT;
		my @ret = map {chomp; $_} (<READ>);
		close READ;
		waitpid $pid, 0;
		if (wantarray) { return @ret; }
		else { return join("\n",@ret); }
	}
	#elsif ($cmd =~ s/^_// && grep /^$cmd/, @{$self->{zoid}->Commands->list}) { # Zoidberg::Commands
	#	return $self->{zoid}->Commands->parse(join(' ', @_));
	#}
	else { $self->{zoid}->print("Huh, \"$cmd\" !? I don't believe there is such a command" , 'error'); }

}

1;
__END__

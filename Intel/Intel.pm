package Zoidberg::Intel;

our $VERSION = '0.04';

use Zoidberg::StringParse;
use base 'Zoidberg::Fish';

use strict;
use Data::Dumper;
use Devel::Symdump;

# TODO
# file expansion in statements

# history lijkt nog niet goed aan te vullen (?)

sub init {
    my $self = shift;
    $self->{parser} = Zoidberg::StringParse->new($self->parent->{grammar}, 'space_gram');
    $self->{context} = {
	'PERL' => 'c_perl',
	'ZOID' => 'c_zoid',
	'SYSTEM' => 'c_system',
    };
    $self->{default} = {
	'PERL' => [qw/f_perl_functions_and_subs f_perl_vars/ ],
	'ZOID' => [qw/f_references f_objects/],
	'SYSTEM' => [qw/f_files_in_path f_home_dirs f_files_and_dirs f_objects/],
	'DEFAULT' => [qw/f_history/],
    };
    return 1;
}

sub tab_exp {
	my $self = shift;
	my $scratch = shift;
	my $context = shift;
	#print "\ndebug: scratch: --$scratch-- context: --$context--\n";
	my ($pref, $poss, $postf, $old_arg, $arg) = ('', [], '', '');

	my $sub = $self->is_special($scratch, $context) || $self->{context}{$context};
	my @dus = ();
	if ($sub =~ /(\(.*\))\s*$/) {
		@dus = eval($1);
		$sub =~ s/(\(.*\))\s*$//;
	}
	if ($sub) { ($pref, $poss, $postf, $old_arg, $arg) = $self->$sub($scratch, $poss, @dus); }
	unless (@{$poss}) { ($pref, $poss, $postf, $old_arg, $arg) = $self->default($scratch, $poss, @dus); }
	#print "debug possible is: ".join("--", @poss)."\n";

	if (($#{$poss} == 0) && $poss->[0]) {
		# recombine
		my $new_arg = $pref.$poss->[0].$postf;
		$scratch =~ s/\Q$old_arg\E$/$new_arg/;
		#print "debug: made $scratch\n";
		return [$scratch];
	}
	else {
		my $new_arg = $self->compair(@{$poss});
		#print "\ndebug: old_arg: \"$old_arg\" pref: \"$pref\" arg: \"$arg\" new arg: \"$new_arg\"\n";
		if ((defined $new_arg) && ($pref.$new_arg =~ /^$arg/)) { $scratch =~ s/\Q$old_arg\E$/$pref$new_arg/; }
		return [$scratch, @{$poss}];
	}

}

sub compair {
	my $self = shift;
	my $first = shift;
	my $lengte = length($first);
	for (@_) { unless ($_ =~ m/^\Q$first\E/i) { while ($_ !~ m/^\Q$first\E/i) { $first = substr($first, 0, length($first)-1); } } } # :))
	return $first;
}

sub test_regex {
	my $self = shift;
	my $arg = shift;
	eval {my $test = 'dit is dus een string'; $test =~ m/$arg/} ; #sanity check
	if ($@) {
		$self->parent->print("\n".$@);
		return (0);
	}
	else { return 1;}
}

sub cut_double { # verwijder dubbelen
	my $self = shift;
	my $poss = shift;
	my @dus = ();
	foreach my $ding (@{$poss}) { unless ( grep {$_ eq $ding} @dus ) { push @dus, $ding }; }
	return [@dus];
}

sub check_glob {
	my $self = shift;
	my $arg = shift;
	if ($self->{config}{no_regex_but_glob}) {
		# globbing to regex -- untested have to look into this sometime
		$arg =~ s/([\*\?])/\.$1/g;
	}
	return $arg;
}

sub is_special {
	my $self = shift;
	my ($scratch, $context) = @_;
	if ($context eq 'SYSTEM') {
		$scratch =~ m/^\s*(\w+)\s/;
		if ($1 && $self->{config}{special}{$1}) { return $self->{config}{special}{$1}; }
		elsif ($scratch =~ /^\!/) { return 's_hist'; } #vunzig en niet transparant -- iets met rules ?
		elsif ($scratch =~ /^_\w*$/) { return 's_command'; }
	}
	else { return "" }
}

sub escape_all {
	my $self = shift;
	my $string = shift;
	$string =~ s/([ \`\&\"\'\(\)\{\}\[\]\|\>\<\*\?\%\$\!\~])/\\$1/g; #" :(
	return $string;
}

sub c_zoid {
	my $self = shift;
	my ($scratch, $poss) = @_;
	my ($pref, $postf) = ('', '');
	my $old_arg = $scratch;
	$scratch = $self->check_glob($scratch);
	unless ($self->test_regex($scratch)) { return ('', [], '', '', ''); }
	foreach my $sub (@{$self->{default}{ZOID}}) { # first result is the one we want
		unless (@{$poss}) { ($pref, $poss, $postf) = $self->$sub($scratch, $poss); }
	}
	return ($pref, $poss, $postf, $old_arg, $scratch);
}

sub c_system {
	my $self = shift;
	my ($scratch, $poss) = @_;
	my ($pref, $postf) = ('', '');
#	print "debug: ".Dumper($self->{parser}->parse($scratch, 'space_gram'))."\n";
	my $tree = [map {$_->[0]} @{$self->{parser}->parse($scratch, 'space_gram', 1)}];
	my $old_arg = $tree->[-1]; # for substituting after $arg is modified
	$tree->[-1] = $self->check_glob($tree->[-1]);
	unless ($self->test_regex($tree->[-1])) { return ('', [], '', '', ''); }
	foreach my $sub (@{$self->{default}{SYSTEM}}) { # first result is the one we want
		unless (@{$poss}) { ($pref, $poss, $postf) = $self->$sub($tree, $poss); }
	}
	return ($pref, $poss, $postf, $old_arg, $tree->[-1]);
}

sub c_perl {
	my $self = shift;
	my ($scratch, $poss) = @_;
	my ($pref, $postf) = ('', '');
	$scratch =~ m/([\$\%\@\&]?\w*)$/;
	my $old_arg = $1;
	my $arg = $old_arg;
	$arg =~ s/([\$\%\@\&])/\\$1/g;
	foreach my $sub (@{$self->{default}{PERL}}) { # first result is the one we want
		unless (@{$poss}) { ($pref, $poss, $postf) = $self->$sub($scratch, $arg, $poss); }
	}
	return ($pref, $poss, $postf, $old_arg, $arg);
}

sub default {
	my $self = shift;
	my ($scratch, $poss) = @_;
	my ($pref, $postf, $old_arg, $arg) = ('', '', '', '');
	foreach my $sub (@{$self->{default}{DEFAULT}}) { # first result is the one we want
		unless (@{$poss}) { ($pref, $poss, $postf, $old_arg, $arg) = $self->$sub($scratch, $poss); }
	}
	return ($pref, $poss, $postf, $old_arg, $arg);
}

####################
##### filters  #####
####################

sub f_stub { # stub sub for filter subs
	my $self = shift;
	# my ($pref, $postf, $tree, $poss) = ('', '', @_); # for SYSTEM filters
	# my ($pref, $postf, $scratch, $poss) = ('', '', @_); # for ZOID filters
	# my ($pref, $postf, $scratch, $arg, $poss) = ('', '', @_); # for PERL filters
	# my ($pref, $postf, $old_arg, $arg, $scratch, $poss) = ('', '', '', '', @_); # for DEFAULT filters
	# insert code here
	# return ($pref, $poss, $postf); # for SYSTEM && ZOID && PERL filters
	# return ($pref, $poss, $postf, $old_arg, $arg); # for DEFAULT filters
}

######################
#### ZOID filters ####
######################

sub f_references { # take in account all kinds of refs: object, hash, array -- do this recursive
	my $self = shift;
	my ($pref, $postf, $arg, $poss) = ('', '', @_);
	if ($arg =~ /\s*->/) {
		$arg =~ s/^(\s*->)//;
		$pref = $1 || '';
		my $tail = $arg;
		$tail =~ s/^(.+->)*//;
		my $name = $1;
		if ($tail =~ /^(([\[\{].*?[\]\}])*)(.*)$/) {
			$name .= $1;
			$tail = $3;
		}
		if ($pref) {
			$pref .= $name;
			$name = '$self->parent->'.$name;
		}
		else {
			$name =~ /^(.+?)->(.*)/;
			my ($obj, $rest) = ($1, $2);
			$pref = $1.'->'.$2;
			$obj =~ s/^\s*//;
			($obj) = grep {/^$obj$/i} @{$self->parent->list_objects};
			$name = "\$self->parent->\{objects\}\{$obj\}->$rest";
		}
		$name =~ s/(\s*->)?$//;
		#print "debug: name: $name, tail: $tail, pref: $pref\n";

		my $ding = eval($name);
		unless (ref($ding)) { # $ding is scalar
			unless (@{$poss}) {
				@{$poss} = ($ding);
				$pref = "";
			}
		}
		elsif (ref($ding) eq 'HASH') { push @{$poss}, sort grep {/^$tail/} map {'{'.$_.'}'} keys %{$ding}; }
		elsif (ref($ding) eq 'ARRAY') {
			my @numbers = ();
			for (0..$#{$ding}) {push @numbers, $_; }
			push @{$poss}, grep {/^$tail/} map {s/([\[\]])/\\$1/g; '\\['.$_.'\\]'} @numbers; # second map to get escaping right
		}
		elsif (ref($ding) eq 'CODE') { @{$poss} = ("\'$name\' is a CODE reference", " "); } # do nothing (?)
		else { # $ding is object
			my $object = eval($name);
			my $subs = $self->s_subs_and_atrr( [], $object, $tail);
			if ($name eq '$self->parent') { # special case
				unless ($self->parent->{core}{show_core}) {
					push @{$poss}, sort grep {/^$tail/i} map {"{$_}"} @{$self->parent->{core}{non_core_keys}}
				}
				else {push @{$poss}, @{$subs};}
				my (undef, $objs) = $self->f_objects([$tail], []);
				push @{$poss}, @{$objs};
			}
			else {push @{$poss}, @{$subs};}
		}
	}
	return ($pref, $poss, $postf);
}

######################
#### Multi context filter ####
######################

sub f_objects {
	my $self = shift;
	my ($pref, $postf, $tree, $poss) = ('->', '', @_);
	my $arg;
	if (ref($tree)) { $arg = $tree->[-1]; }
	else { $arg = $tree; }
	if ($arg =~ /^(\s*-)$/) { return ('', [$1.'>']); } # '-' to '->'
	if ($arg =~ s/^(\s*->)//) { $pref = $1; }
	push @{$poss}, sort grep {/^$arg/i} map {$_."->"} @{$self->parent->list_objects};
	return ($pref, $poss);
}

#################
#### SYSTEM filters ####
#################

sub f_home_dirs {
	my $self = shift;
	my ($pref, $postf, $tree, $poss) = ('', '', @_);
	my $arg = $tree->[-1];
	if ($arg =~ /^~[^\/]*$/) {
		$arg =~ s/^~//;
		#$arg =~ s/\\//g;
		setpwent; # Resets lookup processing.
		my @users = ();
		while (my @info = getpwent) { push @users, $info[0]; } # Returns ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell).
		push @{$poss}, sort grep {/^$arg/} map {$_ .= '/'; $_ = $self->escape_all($_)} @users;
		$pref = "~";
	}
	return ($pref, $poss, $postf);
}

sub f_files_in_path {
	my $self = shift;
	my ($pref, $postf, $tree, $poss) = ('', '', @_);
	my $arg = $tree->[-1];
	unless (($arg =~ /^(\.\/|\/)/) || ($#{$tree} > 0)) {
		push @{$poss}, sort grep { m/^$arg/} map {$self->escape_all($_)} @{$self->parent->list_path};
	} # push path unless "./" or "/" or not begin of statement
	return ($pref, $poss, $postf);
}

sub f_files_and_dirs {
	my $self = shift;
	my ($pref, $postf, $tree, $poss) = ('', '', @_);
	my $arg = $tree->[-1];
	if ($arg =~ /^\\_/) {  $arg =~ s/^\\_/_/; } #escape sequence for files with "^_" # hoort dit hier ? -- NEEN
	$arg =~ /^(\/?(.*[^\\]\/)?)(.*)$/;
	$pref = $1;
	my $tail = $3;
	#$tail =~ s/\\//g;
	#print "\ndebug: tail: --$tail-- TODO\n";
	my $dir = $self->{parent}->abs_path($pref); # if join(@dirs) is empty PWD -- i hope
	my $dir_c = $self->{parent}->scan_dir($dir);
	push @{$poss}, sort grep { m/^$tail/ } map {$self->escape_all($_)."/"} @{$dir_c->{dirs}};
	push @{$poss}, sort grep { m/^$tail/ } map {$self->escape_all($_)} @{$dir_c->{files}};
	if ($arg =~ /^_/) { map {"\\".$_} @{$poss}; } # replace escape
	if (($#{$poss} == 0) && ($poss->[0] !~ /\/$/)) { $postf = " "; }
	return ($pref, $poss, $postf);
}

#################
#### PERL filters ####
#################

sub f_perl_functions_and_subs {
	my $self = shift;
	my ($pref, $postf, $scratch, $arg, $poss) = ('', ' ', @_);
	my @subs = ();
	$scratch =~ s/$arg$//;
	$scratch =~ s/sub\s+(\w+)/push @subs, $1;/ge;
	if ($arg =~ s/^\\\&//) {
		push @{$poss}, grep {/^$arg/} @subs;
		$pref = '&';
	}
	else { push @{$poss}, grep {/^$arg/} (@{$self->{parent}->{grammar}{perl_functions}}, @subs); }
	return ($pref, $poss, $postf);
}

sub f_perl_vars {
	my $self = shift;
	my ($pref, $postf, $scratch, $arg, $poss) = ('', '', @_);
	$scratch =~ s/$arg$//;
	if ($arg =~ s/^\\([\$\%\@])//) {
		$pref = $1;
		if ($pref eq '%') {
			my @hashes = ();
			$scratch =~ s/\%(\w+)/push @hashes, $1;/ge;
			push @{$poss}, grep {/^$arg/} @hashes;
		}
		elsif ($pref eq '@') {
			my @arrays = ();
			$scratch =~ s/\@(\w+)/push @arrays, $1;/ge;
			push @{$poss}, grep {/^$arg/} @arrays;
		}
		else {	# $sigil eq '$'
			my @vars = ();
			$scratch =~ s/\$(\w+)/push @vars, $1;/ge;
			push @{$poss}, grep {/^$arg/} @vars;
			my @hashes = ();
			$scratch =~ s/\%(\w+)/push @hashes, $1;/ge;
			push @{$poss}, map {$_.'{'} grep {/^$arg/} @hashes;
			my @arrays = ();
			$scratch =~ s/\@(\w+)/push @arrays, $1;/ge;
			push @{$poss}, map {$_.'['} grep {/^$arg/} @arrays;
		}
	}
	return ($pref, $poss, $postf);
}

#####################
#### DEFAULT filters ####
#####################

sub f_history {
	my $self = shift;
	my ($pref, $postf, $old_arg, $arg, $scratch, $poss) = ('', '', '', '', @_);

	push @{$poss}, grep {/^$scratch/} $self->parent->History->get_hist;
	$poss = $self->cut_double($poss);

	return ($pref, $poss, $postf, $scratch, $scratch);
}

##################
#### special filters ####
##################

sub s_subs_and_atrr {
	my $self = shift;
	my ($poss, $object, $arg) = @_;
	my $class = ref($object);
	if ($object && $class) { # print "\ndebug: object: $object -- class: $class \n";
		push @{$poss}, sort grep {/^$arg/i} map{"{$_}"}keys %{$object};
		push @{$poss}, sort grep {/^$arg/i} map {s/^(.+\:\:)*//g; $_} (Devel::Symdump->new($class)->functions);
	}
	return $poss;
}

sub s_file_ext { # grep files ending on some ext in @ext or on "/" - this are dirs
    my $self = shift;
    my ($poss, $ext) = @_;
    my $expr = '('.join( '|', (@{$ext}, '\/') ).')';
    @{$poss} = grep {m/\.$expr$/} @{$poss};
    return $poss;
}

#########################
##### special plugs #####
#########################

sub s_command {
	my $self = shift;
	my ($scratch, $poss) = @_;
	my $comm;
	if ($scratch =~ /^\s*_\s*(\w*)$/) {
		$comm = $1 || '';
		# print "debug : commands: ".join('--', @{$self->parent->Commands->list})."\n";
		push @{$poss}, grep {/^$comm/} @{$self->parent->Commands->list};
	}
	return ('', $poss, ' ', $comm, $comm);
}

sub s_hist { # history __i feel lucky__ function
	my $self = shift;
	my ($scratch, $poss) = @_;
	if ($scratch =~ /^\s*\!/) {
		$scratch =~ s/^\s*\!\s*//;
		push @{$poss}, (grep {/^$scratch/} $self->parent->History->get_hist)[0];
	}
	return ('', $poss, ' ', $scratch, $scratch);
}

sub s_help {
	my $self = shift;
	my ($scratch, $poss) = @_;
	$scratch =~ m/(\w*)$/;
	my $arg = $1;
	push @{$poss}, grep {/^$arg/i} @{$self->parent->Help->list};
	return ('', $poss, ' ', $arg, $arg);
}

sub s_mime {
	my $self = shift;
	my ($scratch, $poss) = @_;
	my $type = shift;

	my $arg = ( map {$_->[0]} $self->{parser}->parse($scratch, 'space_gram', 1) )[-1];
	(undef, $poss) = $self->f_files_and_dirs([$arg], $poss); # fetch files

	if (ref($self->{mime}{$type}) && (ref($self->{mime}{$type}) eq "ARRAY") ) { # should be array of extensions
		my $poss = $self->f_file_ext($poss, $self->{mime}{$type});
	}
	else {} # magic mime type or something ..

	return ('', $poss, ' ', $arg, $arg);
}

1;
__END__

=head1 NAME

Zoidberg::Intel - Zoidberg module handling tab expansion and globbing

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This class provides intelligence for tab-expansion
and similar functions. It is very dynamic structured.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 tab_exp($string)

  try to expand $string
  returns ($bit, [$string, @possebilities])
  if $bit is 1 there is a exact match $string
  and thus @possebilities is empty

=head2 default()

  default action, uses filters

=head2 f_*()

  dynamic filters to try all kinds of things

=head2 s_*()

  special actions, used instead of default

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net.

=cut

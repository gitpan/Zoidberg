package Zoidberg::Intel;

use base 'Zoidberg::Fish';

use strict;
use Data::Dumper;
use Devel::Symdump;

#TODO:
#aanvullen to zover ze hetzelfde zijn:) quantum!!!!!!
#_command
#->method:)
# sub tab_exp uit elkaar trekken naar meerdere subs => filters

sub init {
    my $self = shift;
    $self->{parent} = shift;
    $self->{config} = shift;
    $self->{special} = {};
    $self->defaults;
	$self->{special} = $self->parent->pd_merge($self->{special},$self->{config}{special});
    return 1;
}

sub defaults {
	my $self = shift;
    $self->{special}{help} = 's_help';
}

sub tab_exp {
	# todo
	# aanvullen tot zover als candidaten hetzelfde zijn - zie tag

	my $self = shift;
	my $scratch = shift;
	my @poss = ();
	my $pref = "";

	#fetch last args
	$scratch =~ /(([^\s\n]+)[\s\n]+)?([^\s\n]*)$/;
	my $arg = $3;
	my $prev = $2;
	#print "debug: arg is $arg prev is $prev\n";

	if ($prev && (my $sub = $self->is_special($arg, $prev, $scratch))) {
		my @return = $self->$sub($scratch, $prev, $arg, $pref, [@poss]);
		$pref = shift @return;
		@poss = @{shift @return};
	}
	else {
		my @return = $self->default($scratch, $prev, $arg, $pref, [@poss]);
		$pref = shift @return;
		@poss = @{shift @return};
	}

	#print "debug possible is: ".join("--", @poss)."\n";

	if (($#poss == 0) && $poss[0]) {
		# recombine
		my $new_arg = $pref.$poss[0];
		$scratch =~ s/$arg$/$new_arg/;
		#print "debug: made $scratch\n";
		return (1, [$scratch]);
	}
    	else {
		# aanvullen HIER
		return (0, [$scratch, @poss]);
	}

}

sub is_special {
	my $self = shift;
	my ($arg, $prev, $scratch) = @_;
	if ($self->{special}{$prev}) { return $self->{special}{$prev}; }
	else { return "" }
}

sub s_help {
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	my @return = $self->f_objects($scratch, $prev, $arg, $pref, [@poss]);
	$pref = shift @return;
	@poss = map {s/->$//;$_} @{shift @return};
	push @poss, grep {/^$arg/i} ("aliases", "objects");
	#print "debug possible is: ".join("--", @poss)."\n";
	return ($pref, [@poss]);
}

sub default {
	# Hierarchie:
	#	_command
	#	object->sub
	#	files_in_path
	#	home dirs
	#	files & dirs
	#	objects
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};

	foreach my $sub ("f_command", "f_methods", "f_files_in_path", "f_home_dirs", "f_files_and_dirs", "f_objects") {
		unless (@poss) {	# first result is the one we want
			my @return = $self->$sub($scratch, $prev, $arg, $pref, [@poss]);
			$pref = shift @return;
			@poss = @{shift @return};
		}
	}

	return ($pref, [@poss]);
}

sub f_stub { # stub sub for filter subs
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	# insert code here
	return ($pref, [@poss]);
}

sub f_command {
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	if ($arg =~ /^_/) {
        	$arg =~ s/^_//;
        	push @poss, grep /^$arg/i,@{$self->parent->commands->list};
		$pref = "_";
        }
	return ($pref, [@poss]);
}

sub f_methods {
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	if ($arg =~ /(.+)->(.*)$/i) {
		#print "debug: matches \"object->\"\n";
        	my $object = $1;
        	my $tail = $2;
        	($object) = grep/^$object$/i, @{$self->parent->list_objects}; # makes the thing case insensitive
        	if (my $class = ref($self->parent->{objects}{$object})) {
			push @poss, grep {/^$tail/i} map {s/^(.+\:\:)*//g;$_} Devel::Symdump->new($class)->functions;
			#print "debug possible is: ".join("--", @poss)."\n";
			$pref = $object."->";
		}
    	}
	return ($pref, [@poss]);
}

sub f_home_dirs {
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	if ($arg =~ /^~[^\/]*$/) {
		$arg =~ s/^~//;
		setpwent; # Resets lookup processing.
		my @users = ();
		while (my @info = getpwent) { push @users, $info[0]; } # Returns ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell).
		push @poss, map {$_."/"} grep {/^$arg/} @users;
		$pref = "~";
	}
	return ($pref, [@poss]);
}

sub f_files_in_path {
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	unless ($arg =~ /^(\.\/|\/)/) { push @poss, grep { m/^$arg/} keys %{$self->{parent}{cache}{path}}; } # push path unless "./" or "/"
	return ($pref, [@poss]);
}

sub f_files_and_dirs {
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	# check files and dirs
	# fetch dir
	if ($arg =~ /^\\_/) {  $arg =~ s/^\\_/_/; } #escape sequence for files with "^_"

	$arg =~ /^(\/?(.*[^\\]\/)?)(.*)$/;
	$pref = $1;
	my $tail = $3;

	#print "debug prefix is $pref tail is $tail\n";
	my $dir = $self->{parent}->abs_path($pref); # if join(@dirs) is empty PWD -- i hope

	# fetch candidates
	#print "debug: expanding for dir $dir\n";
	my %dir = $self->{parent}->scan_dir($dir);
	push @poss, grep { m/^$tail/ } @{$dir{files}};
	push @poss, grep { m/^$tail/ } map {$_."/"} @{$dir{dirs}};
	#print "debug possible is: ".join("--", @poss)."\n";
	if ($arg =~ /^_/) { map {"\\".$_} @poss; } # replace escape

	return ($pref, [@poss]);
}

sub f_objects {
	my $self = shift;
	my ($scratch, $prev, $arg, $pref) = @_[0..3];
	my @poss = @{$_[4]};
	#check objects if no file or dir matches
	push @poss, grep {/^$arg/i} map {$_."->"} @{$self->parent->list_objects};
	return ($pref, [@poss]);
}

#########################
##### special plugs #####
#########################

sub s_video {
    my $self = shift;
    my ($scratch, $prev, $arg, $pref) = @_[0..3];
    my @poss = @{$_[4]};
    my @return = $self->f_files_and_dirs($scratch, $prev, $arg, $pref, [@poss]);
    $pref = shift @return;
    @return = $self->s_file_ext([qw/avi mpg mpeg rm mov/],$scratch, $prev, $arg, $pref, [@{shift@return}]);
    $pref = shift @return;
    push @poss, @{shift@return};
    return ($pref,[@poss]);
}
 
sub s_audio {
    my $self = shift;
    my ($scratch, $prev, $arg, $pref) = @_[0..3];
    my @poss = @{$_[4]};
    my @return = $self->f_files_and_dirs($scratch, $prev, $arg, $pref, [@poss]);
    $pref = shift @return;
    push @poss, @{shift@return};
    return ($pref,[@poss]);
}

sub s_file_ext {
    my $self = shift;
    my @ext = @{shift()};
    $self->print("deze extensies greppen: ".join(".",@ext)." uit files: [".join(" | ",@{$_[4]})."]");
    my ($scratch, $prev, $arg, $pref) = @_[0..3];
    my @poss = grep {
        my $t;
        foreach my $ex (@ext) {
            /\.$ex$/i
                ||
            $t++;
        }
        !$t;
    } @{$_[4]};
    return ($pref, [@poss]);
}
 
1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Zoidberg::Intel - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::Intel;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Zoidberg::Intel, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.


=head1 AUTHOR


Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.


=head1 SEE ALSO

L<perl>.

=cut

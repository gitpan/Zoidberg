package Zoidberg::Commands;

our $VERSION = '0.1';

use Devel::Symdump;
use Data::Dumper;
use strict;

use base 'Zoidberg::Fish';

sub parse {
	my $self = shift;
	my $com = shift;
	my @opts = map {$_->[0]} @{$self->parent->{StringParser}->parse($com, 'space_gram')};
	$com = shift @opts; 
	$self->parent->print("Commands: \'$com\' options: \'".join('\', \'', @opts).'\'', 'debug');
	if ($com =~ /^\d+$/) {	# multiply
		my $string = join(" ", @_);
		my $re = "";
		for (1..$com) {
			$self->parent->{exec_topic} = $_;
			$re = $self->{parent}->parse(join(' ', @opts));
		}
		if ($com == 8) { $self->parent->MOTZ->eightball('disc'); } # easter egg :)
		return $re;
	}

	my $sub = "";
	if ($com =~ /^_/) { $sub = $com; }
	elsif (defined $self->{config}{aliases}{$com}) { $sub = $self->{config}{aliases}{$com}; }
	elsif ($self->can('c_'.$com)) { $sub = 'c_'.$com; }

	if ($sub) {
		$sub =~ s/^(_(->)?|->)/parent->/;
		if ($sub =~ s/(\(.*\))\s*$//) { unshift @opts, eval($1); }
		my $e_sub = eval("sub { \$self->$sub(\@_) }");
		return $e_sub->(@opts);
	}
	else {
		$self->{parent}->print("Unknown command.", 'error');
		return "";
	}
}

sub intel {
	my $self = shift;
	my ($set, $block, $intel) = @_;

	if ($block =~ /^\s*(\w+)?$/) {
		if (defined ($set = $intel->set_arg($set, $1))) {
			push @{$set->{poss}}, sort grep /$set->{arg}/, @{$self->list};
			$set->{postf} = ' ';
			$intel->add_poss($set);
		}
	}
	else { $intel->parse($set, 'FILE'); }

	return $set;
}

sub c_exec {
	my $self = shift;
	$self->{parent}->parse(join(" ", @_));
	$self->parent->exit;
}

sub c_eval {
	my $self = shift;
	$self->{parent}->parse(join(" ", @_));
	return $self->parent->{exec_error};
}

sub c_source {
	my $self = shift;
	my $file = shift || $self->{parent}->{exec_topic};
	$file = $self->parent->abs_path($file);
	$self->{parent}->{exec_topic} = $file;
	open IN, $file || ($self->parent->print("source: nossuch file: $file", 'error') && return "");
	my $body = join('', (<IN>));
	close IN;
	return $self->parent->parse($body);
}

sub c_set_env {
	my $self = shift;
	my $string = join(" ", @_);
	if ($string =~ m/^\s*(\w*)\s*=\s*\"?(.*?)\"?\s*$/) { $ENV{uc($1)} = $2; }
	else { $self->parent->print("set_env: syntax error", 'error'); }
}

sub c_change_dir {
	# argumenten: dir, no-hist-bit
	my $self = shift;
	my $dir = shift || $self->{parent}->{exec_topic} || $ENV{HOME};
	my $target = $self->{parent}->abs_path($dir);
	#print "Debug: target: --$target--\n";
	$target =~ s/(?<!^)\/$//; #/
	my $no_hist = shift;
	my $last = $ENV{PWD};
	unless (chdir($target)) { $self->{parent}->print("Could not change to dir $target", 'error'); return 0}
	else {
		$ENV{PWD} = $target;
		$self->{parent}->{exec_topic} = $target;
		unless ($no_hist) { $self->parent->History->add_dir($last); }
		#print "debug: changed from $last to $ENV{PWD}\n";

	}
    return 1;
}

sub c_change_dir_f { #change dir fancy
	#args: cmd, back || forw
	my $self = shift;
	my $act = shift;
	#print "debug: change dir fancy -- gonna $act\n";
	my $dir = $self->parent->History->get_dir($act);
	if ($dir) { $self->c_change_dir($dir, 'no hist !'); }
	else { $self->parent->print('Dir history is empty.', 'warning'); }
}

sub c_pwd {
    my $self = shift;
    $self->parent->print($ENV{PWD});
    $ENV{PWD};
}

sub c_delete_object {
	my $self = shift;
	if (my $zoidname = shift) {
		if ($self->{parent}{objects}{$zoidname}->can('isFish') && $self->{parent}{objects}{$zoidname}->isFish) {
			$self->{parent}{objects}{$zoidname}->round_up;
		}
		delete $self->{parent}{objects}{$zoidname};
	}
	else { $self->{parent}->print("Usage \$command \$object_name")}
}

sub c_load_object {
	my $self = shift;
	if (my $name = shift) {
		if (my $class = shift) {
			$self->{parent}->init_postponed($name, $class, @_);
		}
		else { $self->{parent}->print("Usage \$command \$object_name \$class_name")}
	}
	else { $self->{parent}->print("Usage \$command \$object_name \$class_name")}
}

sub c_hide {
	my $self = shift;
	my $ding = shift || $self->{parent}->{exec_topic};
	if ($ding =~ m/^\{(\w*)\}$/) {
		@{$self->parent->{core}{clothes}{keys}} = grep {$_ ne $1} @{$self->parent->{core}{clothes}{keys}};
	}
	elsif ($ding =~ m/^\w*$/) {
		@{$self->parent->{core}{clothes}{subs}} = grep {$_ ne $ding} @{$self->parent->{core}{clothes}{subs}};
	}
}

sub c_unhide {
	my $self = shift;
	my $ding = shift || $self->{parent}->{exec_topic};
	$self->{parent}->{exec_topic} = '->'.$ding;
	if ($ding =~ m/^\{(\w*)\}$/) { push @{$self->parent->{core}{clothes}{keys}}, $1; }
	elsif (($ding =~ m/^\w*$/)&& $self->parent->can($ding) ) {
		push @{$self->parent->{core}{clothes}{subs}}, $ding;
	}
	else { $self->parent->print('Dunno such a thing', 'error'); }
}

sub c_print {
	my $self = shift;
	my $statement = join(" ", @_) || $self->{parent}->{exec_topic};
	$self->{parent}->{exec_topic} = $statement;
	my $ding = $self->{parent}->parse($statement);
	if ((ref($ding) eq 'ARRAY') && ($#{$ding} == 0)) { $ding = $ding->[0]; }
	$self->{parent}->print($statement.' = ', '', 'n');
	$self->{parent}->print($ding);
	return $ding;
}

sub c_echo {
	my $self = shift;
	my $string = join(" ", @_) || $self->{parent}->{exec_topic};
	$self->{parent}->{exec_topic} = $string;
	$self->{parent}->print($string);
	return 1;
}

sub c_quit {
	my $self = shift;
	if (@_) { $self->{parent}->print(join(" ", @_)); }
	$self->{parent}->History->del; # leave no trace
	$self->{parent}->exit;
}

sub list {
	my $self = shift;
	my @commands = keys %{$self->{config}{aliases}};
	push @commands, map {s/^c_//;$_} grep {/^c_/} map {s/^(.+\:\:)*//g; $_} (Devel::Symdump->new(ref($self))->functions);
	return [sort(@commands)];
}


1;
__END__

=head1 NAME

Zoidberg::Commands - Zoidberg plugin for internal commands

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This object handles internal commands
for the Zoidberg shell, it is a core object.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 parse($command, @options)

  Execute command $command

=head2 c_*

  Methods bound to specific commands

=head2 list()

  List commands

=head2 help()

  Output helpfull text


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

http://zoidberg.sourceforge.net
.
=cut

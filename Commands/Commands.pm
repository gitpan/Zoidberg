package Zoidberg::Commands;
use Data::Dumper;
use Safe;
use strict;

use base 'Zoidberg::Fish';

sub init {
	my $self = shift;
	$self->{parent} = shift;
	$self->{config} = shift;

	$self->defaults;
	#print "debug: defaults ".Dumper($self->{commands});
	$self->{commands} = $self->{parent}->pd_merge($self->{commands}, $self->{config});
}

sub defaults {
	my $self = shift;
	$self->{commands}{quit} = "c_quit";
	$self->{commands}{bye} = "c_quit";
	$self->{commands}{cd} = "c_change_dir";
	$self->{commands}{back} = "c_change_dir_f(\"undo\")";
	$self->{commands}{forw} = "c_change_dir_f(\"redo\")";
	$self->{commands}{dir_hist} = "c_show_dir_hist";
	$self->{commands}{flush_cache} = "c_flush_cache";
	$self->{commands}{reload_path} = "c_reload_path";
	$self->{commands}{set_safe} = "c_set_safe";
	$self->{commands}{reset_safe} = "c_set_safe";
	$self->{commands}{load_object} = "c_load_object";
	$self->{commands}{del_object} = "c_delete_object";
	$self->{commands}{print} = "c_print_return";
	$self->{commands}{set_env} = "c_set_env";
}

sub parse {
	my $self = shift;
	my $com = shift;
	my @opts = @_;
	my $sub = "";
	if (defined $self->{commands}{$com}) {
		$sub = $self->{commands}{$com};
		#print "debug: sub is --$sub--\n";
	}

	if ($sub) {
		if ($sub =~ /(\(.*\))\s*$/) {
			my @dus = eval($1);
			$sub =~ s/(\(.*\))\s*$//;
			unshift @opts, @dus;
		}
		unshift @opts, $com;
		# TODO - "::" parsing and module loading
		 return $self->$sub(@opts);
	}
	else {
		$self->{parent}->print("Unknown command.");
		return "";
	}
}

sub c_change_dir {
	# argumenten: dir, no-hist-bit
	my $self = shift;
	shift;
	my $target = $self->{parent}->abs_path(shift @_);
	my $last = $ENV{PWD};
	unless (chdir($target)) { $self->{parent}->print("Could not change to dir $target"); }
	else {
		$ENV{PWD} = $target;
		unless (shift @_) {
			push @{$self->{parent}->{cache}{dir_hist}}, $last;
			if ($#{$self->{parent}->{cache}{dir_hist}} > $self->{parent}->{cache}{max_dir_hist}) { shift @{$self->{parent}->{cache}{dir_hist}}; }
		}
		#print "debug: changed from $last to $ENV{PWD}\n";
	}
}

sub c_change_dir_f { #change dir fancy
	#args: cmd, undo || redo
	#print "debug: fancy dir change ".join("--", @_)."\n";
	my $self = shift;
	shift;
	my $action = shift;
	if ($action eq "undo") {
		if ( @{$self->{parent}->{cache}{dir_hist}}[-1] ) {
			my $target = pop(@{$self->{parent}->{cache}{dir_hist}});
			unshift @{$self->{parent}->{cache}{dir_futr}}, $ENV{PWD};
			$self->c_change_dir("back", $target, 1);
		}
		else { $self->{parent}->print("No dir history."); }
	}
	elsif ($action eq "redo") {
		if ( @{$self->{parent}->{cache}{dir_futr}}[0] ) {
			my $target = shift(@{$self->{parent}->{cache}{dir_futr}});
			push @{$self->{parent}->{cache}{dir_hist}}, $ENV{PWD};
			$self->c_change_dir("forw", $target, 1);
		}
		else { $self->{parent}->print("No dir future."); }
	}
}

sub c_quit {
	my $self = shift;
	if ($_[0] eq "bye") {$self->{parent}->print("Bye bye.") }	#just to be nice
	$self->{parent}->{shell}{continu} = 0;
	$self->{parent}->del_one_hist;
}

sub c_show_dir_hist {
	my $self = shift;
	my @body = ();
	if (@{$self->{parent}->{cache}{dir_hist}}) {push @body, "Dir history:\n\t".join("\n\t", @{$self->{parent}->{cache}{dir_hist}}); }
	if (@{$self->{parent}->{cache}{dir_futr}}) {push @body, "Dir future:\n\t".join("\n\t", @{$self->{parent}->{cache}{dir_futr}}); }
	if (@body) { $self->{parent}->print(join("\n", @body)); }
	else { $self->{parent}->print("Both dir history and future are empty."); }
}

sub c_flush_cache {
	my $self = shift;
	$self->{parent}->{cache} = {};
	$self->{parent}->{cache}{hist} = [];
	$self->{parent}->{cache}{dir_hist} = [];
	$self->{parent}->{cache}{dir_futr} = [];
}

sub c_reload_path {
	my $self = shift;
	$self->{parent}->cache_path("force");
}

sub c_set_safe {
	my $self = shift;
	shift;
	my $name = shift || "Safe";
	$self->{parent}->init_safe($name, "new");
}

sub c_delete_object {
	my $self = shift;
	shift;
	if (my $name = shift) {
		$self->{parent}{objects}{$name}->round_up;
		delete $self->{parent}{objects}{$name};
	}
	else { $self->{parent}->print("Usage \$command \$object_name")}
}

sub c_load_object {
	my $self = shift;
	shift;
	if (my $name = shift) {
		if (my $class = shift) {
			$self->{parent}->init_postponed($name, $class, @_);
		}
		else { $self->{parent}->print("Usage \$command \$object_name \$class_name")}
	}
	else { $self->{parent}->print("Usage \$command \$object_name \$class_name")}
}

sub c_print_return {
	my $self = shift;
	shift;
	my $string = join(" ", @_); # recombine args
	my $ding = $self->{parent}->parse($string);
	if (ref($ding)) { $self->{parent}->print(Dumper($ding)); }
	else { $self->{parent}->print($ding); }
	return $ding;
}

sub c_set_env {
	my $self = shift;
	shift;
	my $string = join(" ", @_);
	$string =~ /^(.*)=\"(.*)\"/;
	$ENV{$1} = $2;
}

sub list {
	my $self = shift;
	return [sort(keys(%{$self->{commands}}))];
}

sub help {
	my $self = shift;
	return $self->{parent}->print("\n\tDefined comands are:\n\n\t  ".join("\n\t  ",  @{$self->list})."\n\n\tCommands start with an \"_\".\n");
	# TODO more specific help texts
}

sub round_up {

}

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Zoidberg::Commands - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::Commands;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Zoidberg::Commands, created by h2xs. It looks like the
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

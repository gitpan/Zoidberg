package Zoidberg::Test;
use Data::Dumper;

use base 'Zoidberg::Fish';

use strict;

sub init {
	my $self = shift;
	$self->{parent} = shift;
	$self->{config} = shift;
    #require "/data/code/perlinit/ipc.pl";
    #$self->parent->{objects}{Run} = CodeRunner->new;
    #$self->parent->{objects}{Run}->init($self->parent,{});
	$self->{hash} = {
		'hoer' => 'billy',
		'nerd' => 'damian',
	}
}

sub iets {
	my $self = shift;
	$self->{parent}->print("PHP sucks ! ");
}

sub write {
	my $self = shift;
	if ($self->{parent}->pd_write($self->{config}{file}, $self->{hash})) { $self->{parent}->print("Succeeded"); }
	else { $self->{parent}->print("Failed"); }
}

sub dump {
	my $self = shift;
	foreach my $var (@_) {
		my $string = '$self->{parent}->'.$var;
		$self->{parent}->print("Test: $var = ".Dumper(eval($string)));
	}
}

sub ask {
	my $self = shift;
	my $answer = $self->{parent}->ask("Who's your daddy ? ");
	$self->{parent}->print("You said : $answer");
}

sub split {
	my $self = shift;
	my $string = shift;
	my @split = ( '|', '>', '<'); # TODO , '>>', '<<'
	my @limits = ('"', '\'', '`');
	my %nested_limits = (
			'{' => '}',
			'(' => ')',
			'[' => ']'
	);
	my @blocks = $self->split_loop($string, \@split, \@limits, \%nested_limits);
    if ($#blocks == 0) {
        return $self->parent->parse($blocks[0]);
    }
    $self->parent->run->doeBlocks(@blocks)->peval;
	return \@blocks;
}

sub split_loop {
	my $self = shift;
	my $string = shift;
	my @split = @{ shift @_};
	my @limits = @{ shift @_};
	my %n_limits = %{ shift @_};
	my @chars = split(//, $string);
	my @blocks = ();
	my %count = ();
	my $part = "";
	my $last = '';
	foreach my $char (@chars) {
		#print "debug: part $part char $char count ".Dumper(\%count);
		if ($last eq '\\')  { $part .= $char; $last = $char; next } # escaped - next
		my $no_top = 0;
		foreach my $value (values(%count)) {$no_top += $value;} # if one count is up, no top level
		unless ($no_top) {
			if (my ($pijper) = grep {$_ eq $char} @split) { # split in two
				push @blocks, "$part$pijper";
				$part = "";
				next;
			}
			elsif (grep {$_ eq $char} @limits) {
				$part .= $char; $last = $char;
				$count{$char} = $count{$char} ? 0:1; # switch it
				next;
			}
		}
		if (grep {$_ eq $char} keys(%n_limits) ) {	# open block
			$part .= $char; $last = $char;
			$count{$char}++;
		}
		elsif (grep {$_ eq $char} values(%n_limits) ) {	# close block
			$part .= $char; $last = $char;
			my ($key) = grep {$n_limits{$_} eq $char} keys(%n_limits);
			$count{$key}--;
		}
		else { $part .= $char; $last = $char; } #default
	}
	push @blocks, $part;
	return @blocks;
}

sub main {
	my $self = shift;
	$self->{parent}->print("You called Test->main with ".join("--", @_));
}

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Zoidberg::Test - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::Test;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Zoidberg::Test, created by h2xs. It looks like the
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

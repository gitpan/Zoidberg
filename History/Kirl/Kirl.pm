package Zoidberg::History::Kirl;

our $VERSION = '0.04';

use strict;
use Data::Dumper;
use POSIX qw/floor/;
push @Zoidberg::History::Kirl::ISA, ("Zoidberg::PdParse");

# TODO if more dimensions try crossing subsets

sub new {
	my $class = shift;
	my $self = {};
	$self->{config} = shift;
	$self->{input_format} = [qw/comm dir/];
	bless $self, $class;

	unless ($self->{config}{max_entries}) { $self->{config}{max_entries} = 500; }
	if ($self->{config}{kirl_file} && -s $self->{config}{kirl_file}) {
		 $self->{db} = $self->pd_read($self->{config}{kirl_file});
	}
	else { $self->init_db; }
	#print "debug: db: ".Dumper($self->{db});
	return $self;
}

sub init_db {
	my $self = shift;
	$self->{db} = {
		'nodes' => {},		# the actual  data
		'next_id' => 1,		# never assigned id
		'free_ids' => [],		# freed ids
		'death_row' => [],	# ids to delete next
		'last_suggested' => undef, # used for negative feedback
	};
	$self->{db}{root} = $self->insert('kirl_root');
	$self->pardon($self->{db}{root});

	foreach my $type (@{$self->{input_format}}) {
		$self->{db}{$type} = $self->insert($type);
		$self->pardon($self->{db}{$type});
		$self->connect($self->{db}{$type}, $self->{db}{root})
	}

}

#####################
#### external interface ####
#####################

sub remember {
	my $self = shift;
	my ($input, $output) = @_;

	my @input_ids;
	foreach my $type (@{$self->{input_format}}) {
		my $value = shift @{$input};
		if ( (defined $value) && (my $i_id = $self->get($type, $value)) ) {
			push @input_ids, $i_id;
		}
		else {
			my $i_id = $self->insert($value);
			$self->connect($i_id, $self->{db}{$type});
			push @input_ids, $i_id;
		}
	}

	my @sugg = $self->cross('kids', @input_ids);
	my $id = undef;
	if ($id = grep { $self->{db}{nodes}{$_}{data} eq $output } @sugg) {
		$self->{db}{nodes}{$id}{weight}++;
		$self->touch($id);
		foreach my $parent (@input_ids) { $self->touch($parent); }
	}
	else {
		$id = $self->insert($output);
		foreach my $parent (@input_ids) {
			$self->connect($id, $parent);
			$self->touch($parent);
		}
	}
	if ( $self->{db}{last_suggested} && ($id ne $self->{db}{last_suggested}) ) {
		$self->{db}{nodes}{$self->{db}{last_suggested}}{weight}--;
	}
	$self->{db}{last_suggested} = undef;
}

sub suggestion {
	my $self = shift;
	my $input = shift;
	my @input_ids = ();
	foreach my $type (@{$self->{input_format}}) {
		my $value = shift @{$input};
		if ( (defined $value) && (my $i_id = $self->get($type, $value)) ) {
			push @input_ids, $i_id;
		}
	}
	unless (@input_ids) { return ''; }
	my @sugg = $self->cross('kids', @input_ids);
	# TODO if more dimensions try crossing subsets
	unless (@sugg) { return ''; }
	else {
		if (my $id = $self->heaviest(@sugg)) {
			if ($self->{db}{nodes}{$id}{weight} > 1) {
				$self->{db}{last_suggested} = $id;
				return  $self->{db}{nodes}{$id}{data};
			}
			else { return ''; }
		}
		else { return '' ; }
	}
}

sub dream {
	# do some maintenance
}

###################
#### db operations ####
###################

sub get {
	my $self = shift;
	my ($type, $value) = @_;
	foreach my $kid (@{$self->{db}{nodes}{$self->{db}{$type}}{kids}}) {
		if ( $self->{db}{nodes}{$kid}{data} eq $value ) { return $kid; }
	}
}

sub heaviest {
	my $self = shift;
	my @ids = @_;
	my $max = 0;
	my @h_ids = ();
	foreach my $opt (@ids) {
		if ($self->{db}{nodes}{$opt}{weight} > $max) {
			$max = $self->{db}{nodes}{$opt}{weight};
			@h_ids = ($opt);
		}
		elsif ($self->{db}{nodes}{$opt}{weight} == $max) {
			push @h_ids, $opt;
		}
	}
	unless (@{h_ids}) { return undef; }
	elsif ($#h_ids == 0) { return $h_ids[0]; }
	else {
		my $int = floor rand($#h_ids+1);
		return $h_ids[$int];
	}
}

sub cross {
	my $self = shift;
	#print "debug: ".Dumper(\@_);
	my $kind = shift;
	my @ids = @_;
	my @sets = ();
	foreach my $id (@ids) { push @sets, $self->{db}{nodes}{$id}{$kind}; }
	my $ref = shift @sets;
	#print "debug: ".Dumper($ref, \@sets);
	my @sugg = @{$ref};
	foreach my $set (@sets) {
		my @my_sugg = ();
		foreach my $opt (@{$set}) {
			for (@sugg) {
				if ($_ eq $opt) {
					push @my_sugg, $opt;
					last;
				}
			}
		}
		@sugg = @my_sugg;
	}
	return @sugg;
}

#####################
#### node operations ####
####################

sub pardon { # get a node out of death row
	my $self = shift;
	my $id = shift;
	@{$self->{db}{death_row}} = grep {$_ ne $id} @{$self->{db}{death_row}};
}

sub new_id {
	my $self = shift;
	if (@{$self->{db}{free_ids}}) { return shift @{$self->{db}{free_ids}};}
	elsif ($self->{db}{next_id} <= $self->{config}{max_entries}) { return $self->{db}{next_id}++; }
	else {
		my $victim = shift @{$self->{db}{death_row}};
		$self->delete($victim);
		return $victim;
	}
}

sub insert {
	my $self = shift;
	my $data = shift;
	my $id = $self->new_id;
	$self->{db}{nodes}{$id} = { 'id' => $id, 'data' => $data, 'parents' => [], 'kids' => [], 'weight' => 1};
	push @{$self->{db}{death_row}}, $id;
	return $id;
}

sub connect {
	my $self = shift;
	my ($kid, $parent) = @_;
	push @{$self->{db}{nodes}{$parent}{kids}}, $kid;
	push @{$self->{db}{nodes}{$kid}{parents}}, $parent;
}

sub touch {
	my $self = shift;
	my $id = shift;
	@{$self->{db}{death_row}} = grep {$_ ne $id} @{$self->{db}{death_row}};
	push @{$self->{db}{death_row}}, $id;
}

sub delete {
	my $self = shift;
	my $id = shift;
	foreach my $parent ($self->{db}{nodes}{$id}{parents}) {
		@{$self->{db}{nodes}{$parent}{kids}} = grep {$_ ne $id} @{$self->{db}{nodes}{$parent}{kids}};
	}
	push @{$self->{db}{free_ids}}, $id;
	return delete ${$self->{db}{nodes}}{$id};
}

############
#### rest ####
############

sub print {
	my $self = shift;
	print @_;
	print "\n";
}

sub round_up {
	my $self = shift;
	if ($self->{config}{kirl_file}) {
		unless ( $self->pd_write( $self->{config}{kirl_file},  $self->{db}) ) {
			$self->print("Failed to write kirl file: ".$self->{config}{kirl_file}, 'error');
		}
	}
}

sub DESTROY { # als dit een echte subklasse wordt is deze overbodig
	my $self = shift;
	$self->round_up;
}

1;
__END__

=head1 NAME

Zoidberg::History::Kirl - Pattern recognition module for Zoidberg::History

=head1 SYNOPSIS

   stilll unstable

=head1 ABSTRACT

  The purpose of this module is to apply pattern recognition on the zoidberg history.

=head1 DESCRIPTION

The purpose of this module is to apply pattern recognition on the history.
It is in developement and unstable till later notice.

=head2 EXPORT

None by default.


=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::Fish>

L<Zoidberg::History>

http://zoidberg.sourceforge.net

=cut


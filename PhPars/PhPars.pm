package Zoidberg::PhPars;

use strict;
use Storable qw/dclone/;
use Data::Dumper;

sub ph_read_multi {
	my $self = shift;
	my $ref =  {};
	foreach my $file (@_) {
		my $pref = $self->ph_read($file);
		$ref= $self->ph_merge($ref, $pref);
	}
	return $ref;
}

sub ph_read {
	my $self = shift;
	my $file = shift;
	my $cont = "";
	my $bit = open F, $file;
	while (<F>) {  $cont .= $_; };
	close F;
	eval(my %test = eval($cont));
	if (!$@ && $bit) {
		my $ret = eval($cont);
		print "debug: read file $file to ".Dumper($ret)."\n";
		return $ret;
	}
	elsif ($@) {
		print "debug: read $file failed\n";
		$self->print($@."\nConfig file $file could not be loaded.");
		return {};
	}
	else { $self->print("Could not open file $file." ); }
}

sub ph_write {			# not yet debug -- maybe now ...
	my $self = shift;
	my $file = shift;
	my $hash_ref = shift;
	my $bit = open F, ">$file";
	print F $self->ph_stringify($hash_ref, 0)."\n";
	close F;
	return $bit;
}

sub ph_stringify {
	my $self = shift;
	my $ref = shift;
	my $level = shift;
	my $string = "";
	if (ref($ref) eq "HASH") {
		$string = "{\n";
		while (my ($k, $v) = each %{$ref}) {
			if (ref($v)) {
				$string .= ("\t" x $level)."\'$k\' => ".$self->ph_stringify($v, $level+1).",\n";
			}
			else { $string .= ("\t" x $level)."\'$k\' => \"$v\",\n"; }
		}
		$string .= ("\t"x$level)."}";
	}
	elsif (ref($ref) eq "ARRAY") {
		$string = "[\n";
		foreach my $v (@{$ref}) {
			if (ref($v)) {
				$string .= ("\t" x $level).$self->ph_stringify($v, $level+1).",\n";
			}
			else { $string .= ("\t" x $level)."\"$v\",\n"; }
		}
		$string .= ("\t"x$level)."]";
	}
	return $string;
}

sub ph_merge {	# merge multiple hashes
	my $self = shift;
	my @refs = @_;
	@refs = map {ref($_) ? dclone($_) : $_} @refs;
	my $ref = shift @refs;
	foreach my $ding (@refs) {
		while (my ($k, $v) = each %{$ding}) {
			if (ref($v) && defined($ref->{$k})) {
				$ref->{$k} = $self->merge($ref->{$k}, $ding->{$k});	#recurs
			}
			else { $ref->{$k} = $v; }
		}
	}
	return $ref;
}

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Zoidberg::PhPars - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::PhPars;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Zoidberg::PhPars, created by h2xs. It looks like the
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

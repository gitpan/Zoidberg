package Zoidberg::PdParse;

our $VERSION = '0.1';

use strict;

use Data::Dumper;
use IO::File;
use Storable qw/dclone/;
$Data::Dumper::Purity=1;
$Data::Dumper::Deparse=1;
$Data::Dumper::Indent=1;

sub pd_read_multi {
    # @files or [@files], options
    my $self = shift;
    my @files = ();
    my @options = ();
    if (ref($_[0]) eq 'ARRAY') {
    	my $ref = shift;
        @files = @{$ref};
        @options = @_;
    }
    else { @files = @_; }

    my $ref = {};
    for (@files) {
        $ref = $self->pd_merge($ref,$self->pd_read($_, @options));
    }
    return $ref;
}

sub pd_read {
    my $self = shift;
    my $file = shift;
    my $pre_eval = shift || '';
    my $fh = IO::File->new("< $file") or $self->print("Failed to fopen($file): $!\n"),return{};
    my $cont = join("",(<$fh>));
    $fh->close;
    my $VAR1;
    eval($pre_eval.';'.$cont);
    if ($@) {
        $self->print("Failed to eval the contents of $file ($@), no config read\n");
        return {};
    }
    return $VAR1;
}

sub pd_write {
    my $self = shift;
    my $file = shift;
    my $ref = shift;
    my $fh = IO::File->new("> $file") or $self->print("Failed to fopen($file) for writing\n"),return 0;
    $fh->print(Dumper($ref)); #print returns bit
}

sub pd_merge {
    my $self = shift;
    my @refs = @_;
    @refs = map {ref($_) ? dclone($_) : $_} @refs;
    #print "debug trying to merge: ".Dumper(\@refs);
    my $ref = shift @refs;
    foreach my $ding (@refs) {
        while (my ($k, $v) = each %{$ding}) {
            if (defined($ref->{$k}) && ref($v)) {
		if (ref($v) eq 'ARRAY') { push @{$ref->{$k}}, @{$ding->{$k}}; }
		elsif (ref($v) eq 'SCALAR') { $ref->{$k} = $v; }
		else { $ref->{$k} = $self->pd_merge($ref->{$k}, $ding->{$k}); } #recurs for HASH (or object)
            }
            else { $ref->{$k} = $v; }
        }
    }
    return $ref;
}

1;
__END__
=head1 NAME

Zoidberg::PdParse - parses Zoidbergs config files

=head1 SYNOPSIS

  push @ISA, 'Zoidberg::PdParse';
  my $config_hash_ref = $self->pd_read('config_file.pd');

=head1 ABSTRACT

  This module parses Zoidbergs config files.

=head1 DESCRIPTION

The Zoidberg object and some Zoidberg plugins inherit from
this object to read and write config files. The format
used is actually output of Data::Dumper.
We give these files the extension ".pd" this stands for
"Perl Dump".
These files can contain all kinds of code that will
be executed in a eval() function.
There should be assigned a $VAR1 (as done by Data::Dumper
output) preferrably this should be a hash reference.

=head2 EXPORT

None by default.

=head1 METHODS

=head2 pd_read_multi(@file_names)

  Returns a merge of the contents of array files as hash ref.
  Can also be called as pd_read_multi([@file_names], @options)
  in this case @options is passed on to pd_read

=head2 pd_read($file_name, $pre_eval)

  Returns the contents of single file as hash ref.
  $pre_eval can contain perl code as a string,
  this code will be evalled in the same scope as
  the config file. This can for example be used to allow
  variables in the config file.

=head2 pd_write($file, $hash_ref)

  Dump the contents of $hash_ref to $file. Retuns 1 on succes.

=head2 pd_merge(@hash_refs)

  Merges @hash_refs to single ref. This is for example used
  to let multiple config files overload each other.
  The last array element is the las processed, and thus in case of overloading
  the most specific.

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>
Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

http://zoidberg.sourceforge.net.

=cut

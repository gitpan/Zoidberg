package Zoidberg::PdParse;

our $VERSION = '0.3b';

use strict;

require Exporter;

use Data::Dumper;
use IO::File;
use Storable qw/dclone/;

$Data::Dumper::Purity=1;
$Data::Dumper::Deparse=1;
$Data::Dumper::Indent=1;

push @{Zoidberg::PdParse::ISA}, 'Exporter';

@{Zoidberg::PdParse::EXPORT} = qw/pd_read pd_write pd_merge/;
@{Zoidberg::PdParse::EXPORT_OK} = qw/pd_read_multi pd_forget/;

our %read = ();
our $base_dir = './';

sub pd_read_multi {
    # @files or [@files], options
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
        $ref = pd_merge($ref,pd_read($_, @options));
    }
    return $ref;
}

sub pd_read {
    my $file = _file(shift @_);
    my $pre_eval = shift || '';
    if ($read{$file}) { return $read{$file}; }
    elsif (-s $file) {
    	my $fh = IO::File->new("< $file") or return undef;
    	my $cont = join("",(<$fh>));
    	$fh->close;
    	my $VAR1;
    	eval($pre_eval.';'.$cont);
    	if ($@) {
        	print STDERR "Failed to eval the contents of $file ($@), no config read\n";
        	return undef;
    	}
    	$read{$file} = $VAR1;
    	return $read{$file};
    }
    else { return {}; }
}

sub pd_write {
    my $file = _file(shift @_);
    my $ref = shift;
    my $fh = IO::File->new("> $file") or return 0;
    $fh->print(Dumper($ref)); #print returns bit
}

sub pd_merge {
    my $ref = shift;
    foreach my $ding (@_) { 
    	$ding = dclone($ding) if grep {ref($ding) eq $_} qw/HASH ARRAY SCALAR/;
    	$ref = _merge($ref, $ding);
    }
    return $ref;
}

sub _merge {
	my ($ref, $ding) = @_;
	while (my ($k, $v) = each %{$ding}) {
            if (defined($ref->{$k}) && ref($v)) {
                if (ref($v) eq 'ARRAY') { # this one is open for discussion
                        push @{$ref->{$k}}, @{$ding->{$k}};
                }
                elsif (grep {ref($v) eq $_} qw/SCALAR CODE Regexp/) { $ref->{$k} = $v; }
                else { $ref->{$k} = _merge($ref->{$k}, $ding->{$k}); } #recurs for HASH (or object)
            }
            else { $ref->{$k} = $v; }
        }
	return $ref;
}

sub _file {
	# files starting with a / are absolute
	# else relative to base_dir
	my $file = shift;
	unless ($file =~ /^\.{0,2}\//) { # unless / ./ ../
		$base_dir =~ s/\/?$/\//;
		$file = $base_dir.$file;
	}
	return $file;
}

sub pd_forget { %read = (); }

1;
__END__
=head1 NAME

Zoidberg::PdParse - parses Zoidbergs config files

=head1 SYNOPSIS

  use Zoidberg::PdParse;
  $Zoidberg::PdParse::base_dir = $my_config_dir;
  my $config_hash_ref = pd_read('my_config_file.pd');

=head1 ABSTRACT

  This module parses Zoidbergs config files.

=head1 DESCRIPTION

The Zoidberg object and some Zoidberg plugins inherit from
this object to read and write config files. The format
used is actually output of Data::Dumper.
We give these files the extension ".pd" this means
"Perl Dump".
These files can contain all kinds of code that will
be executed in a eval() function.
There should be assigned a $VAR1 (as done by Data::Dumper
output) preferrably this should be a hash reference.

=head2 EXPORT

@EXPORT = qw/pd_read pd_write pd_merge/;

@EXPORT_OK = qw/pd_read_multi pd_forget/;

( This module modifies the global settings of Data::Dumper )

=head1 METHODS

=over 4

=item B<pd_read($file_name, $pre_eval)>

Returns the contents of single file as a hash ref.
$pre_eval can contain perl code as a string,
this code will be evalled in the same scope as
the config file. This can for example be used to allow
variables in the config file.

This function caches read files, use pd_forget to flash cache.
Due to this cache loops between files should not be a problem.

=item B<pd_read_multi(@file_names)>

Returns a merge of the contents of array files as hash ref.
Can also be called as pd_read_multi([@file_names], @options)
in this case @options is passed on to pd_read

=item B<pd_write($file, $hash_ref)>

Dump the contents of $hash_ref to $file. Retuns 1 on succes.

=item B<pd_merge(@hash_refs)>

Merges @hash_refs to single ref. This is for example used
to let multiple config files overload each other.
The last array element is the last processed, and thus in case of overloading
the most specific.

=item B<pd_forget>

Forget read files.

=back

=head1 AUTHOR

R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>
Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

http://zoidberg.sourceforge.net.

=cut

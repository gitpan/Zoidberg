
package Zoidberg::Utils;

our $VERSION = '0.40';

use strict;
use Carp;
use Storable qw/dclone/;
use Zoidberg::Error;
use Zoidberg::PdParse;
use Zoidberg::Output;
use Exporter::Tidy
	output => [qw/debug/],
	other  => [qw/setting read_data_file read_file merge_hash complain/];

our $ERROR_CALLER = 1;

*debug = \&Zoidberg::Output::debug; # FIXME quick hack
*complain = \&Zoidberg::Output::complain; # FIXME quick hack

sub setting {
	# FIXME support for Fish argument and namespace
	my $ref = $ENV{ZOIDREF}->{settings}{shift(@_)};
	return (wantarray && ref($ref) eq 'ARRAY') ? (@$ref) : $ref;
}

sub read_data_file {
	my $file = shift;
	croak 'read_data_file() is not intended for fully specified files, try read_file()'
		if $file =~ m!^/!;
	for my $dir (setting('data_dirs')) {
		for ("$dir/data/$file", map "$dir/data/$file.$_", qw/pd yaml/) {
			next unless -f $_;
			error "Can not read file: $_" unless -r $_;
			return read_file($_);
		}
	}
	error "Could not find file '$file' in (" .join(', ', setting('data_dirs')).')';
}

sub read_file {
	my $file = shift;
        error "no such file: $file\n" unless -f $file;

	my $ref;
	if ($file =~ /^\w+$/) { todo 'executable data file' }
	elsif ($file =~ /\.(pd)$/i) { $ref = pd_read($file) }
	elsif ($file =~ /\.(yaml)$/i) { todo qq/yaml data file support\n/ }
	else { error qq/Unkown file type: "$file"\n/ }

	error "The file '$file' did not return a defined value"
		unless defined $ref;
	return $ref;
	
}

sub merge_hash {
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

1;

__END__

=head1 NAME

Zoidberg::Utils - utility library for Zoidberg packages

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

This module bundles common routines used by the Zoidberg 
object classes.

=head1 EXPORT

None by default.

FIXME

=head1 METHODS

FIXME

=over 4

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut



package Zoidberg::Utils;

our $VERSION = '0.53';

use strict;
use vars '$AUTOLOAD';
use Carp;
use Zoidberg::Utils::Error;

our $ERROR_CALLER = 1;

## Funky import/autoload/autouse thingy ##

my %tags = (
	default => [qw/:output :error/],

	output	=> [qw/output message debug/],
	fs	=> [qw/abs_path list_dir/],
	fs_engine => [qw/f_index_path f_wipe_cache f_read_cache f_save_cache/],
	error	=> [qw/error bug todo complain/],
	other	=> [qw/setting read_data_file read_file merge_hash/],

	_fs	=> [qw/abs_path list_path list_dir unique_file/],
	_output	=> [qw/output message debug complain typed_output/],
	_cluster => {
		fs_engine => [qw/Zoidberg::Utils::FileSystem _prefix f_ :engine/],
		_fs	=> [qw/Zoidberg::Utils::FileSystem/],
		_output	=> [qw/Zoidberg::Utils::Output/],
	},
);

my %available;
my $map = delete $tags{_map};
my $cluster = delete $tags{_cluster};
@available{ grep !ref, keys %$map } = () if $map;
@available{ grep !/^:/, map @$_, values %tags } = ();
for my $key (keys %$cluster) { $available{$_} = $key for @{$tags{$key}} }
$tags{all} ||= [ keys %available ];

sub import {
        my ($me, @symbols) = @_;
        my $caller = caller;
        @symbols = @{ $tags{default} } if @symbols == 0 and exists $tags{default};
        my %exported;
        my $prefix = '';
        while (my $symbol = shift @symbols) {
            $symbol eq '_prefix' and ($prefix = shift @symbols, next);
            my $real = $map && exists $map->{$symbol} ? $map->{$symbol} : $symbol;
            next if exists $exported{"$prefix$real"};
            undef $exported{"$prefix$symbol"};
            $real =~ /^:(.*)/ and (
                (exists $tags{$1} or
                    (require Carp, Carp::croak("Unknown tag: $1"))),
                push(@symbols, @{ $tags{$1} }),
                next
            );
            ref $real and (
                $symbol =~ s/^[\@\$%*]//,
                *{"$caller\::$prefix$symbol"} = $real,
                next
            );
            exists $available{$symbol} or 
                (require Carp, Carp::croak("Unknown symbol: $real"));
	    _load($available{$symbol});
            my ($sigil, $name) = $real =~ /^([\@\$%*]?)(.*)/;
            $symbol =~ s/^[\@\$%*]//;
	    no strict 'refs';
            *{"$caller\::$prefix$symbol"} =
                $sigil eq ''  ? \&{"$me\::$name"}
              : $sigil eq '$' ? \${"$me\::$name"}
              : $sigil eq '@' ? \@{"$me\::$name"}
              : $sigil eq '%' ? \%{"$me\::$name"}
              : $sigil eq '*' ? \*{"$me\::$name"}
              : (require Carp, Carp::croak("Strange symbol: $real"));
        }
}

sub _load {
	my $tag = shift;
	return unless defined $tag and exists $$cluster{$tag};
	my ($class, @args) = @{delete $$cluster{$tag}};
	eval "require $class; $class->import(\@args)";
	die if $@;
	undef $_ for grep {defined $_ and $_ eq $tag} values %available;
}

## Various methods ##

sub setting {
	# FIXME support for Fish argument and namespace
	my $key = shift;
	return undef unless exists $Zoidberg::CURRENT->{settings}{$key};
	my $ref = $Zoidberg::CURRENT->{settings}{$key};
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
	error "Could not find 'data/$file' in (" .join(', ', setting('data_dirs')).')';
}

sub read_file {
	my $file = shift;
        error "no such file: $file\n" unless -f $file;

	my $ref;
	if ($file =~ /^\w+$/) { todo 'executable data file' }
	elsif ($file =~ /\.(pl)$/i) { $ref = do $file }
	elsif ($file =~ /\.(pd)$/i) { $ref = pd_read($file) }
	elsif ($file =~ /\.(yaml)$/i) { todo qq/yaml data file support\n/ }
	else { error qq/Unkown file type: "$file"\n/ }

	error "In file $file\: $@" if $@;
	error "File $file did not return a defined value" unless defined $ref;
	return $ref;
}

sub pd_read {
	my $FILE = shift;
	open FILE, '<', $FILE or return undef;
	my $CONTENT = join '', (<FILE>);
	close FILE;
	my $VAR1;
	eval $CONTENT;
	complain("Failed to eval the contents of $FILE ($@)") if $@;
	return $VAR1;
}

sub merge_hash {
    my $ref = {};
    $ref = _merge($ref, $_) for @_;
    return $ref;
}

sub _merge { # Removed use of Storable::dclone - can throw nasty bugs
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

Zoidberg::Utils - an interface to zoid's utility libs

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

This module bundles common routines used by the Zoidberg 
object classes, especially the error and output routines.

It is intended as a bundle or cluster of several packages
so it is easier to keep track of all utility methods.

=head1 EXPORT

By default the ':error' and ':output' tags are exported.

The following export tags are defined:

=over 4

=item :error

Gives you C<error>, C<bug>, C<todo>, C<complain>; the first 3 belong to
L<Zoidberg::Utils::Error>, the last to L<Zoidberg::Utils::Output>.

=item :output

Gives you C<output>, C<message> and  C<debug>, all of which belong to
L<Zoidberg::Utils::Output>.

=item :fs

Gives you C<abs_path> and C<list_dir>, which belong to 
L<Zoidberg::Utils::FileSystem>.

=back

Also methods listen below can be requested for import.

=head1 METHODS

=over 4

=item C<read_data_file($basename)>

Searches in zoid's data dirs for a file with basename C<$basename> and returns
a hash reference with it's contents.

This method should be used by all plugins etc. to ensure portability.

FIXME more explanation

=item C<read_file($file)>

Returns a hash reference with the contents of C<$file>.
Currently only "Data::Dumper files" (.pd) are supported, 
but possibly other formats like yaml will be added later.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

The import function was adapted from L<Exporter::Tidy>
by Juerd Waalboer <juerd@cpan.org>, it was modified to add the
clustering feature.

=head1 SEE ALSO

L<Zoidberg::Utils::Error>, L<Zoidberg::Utils::Output>,
L<Zoidberg::Utils::FileSystem>,
L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


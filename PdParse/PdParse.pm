package Zoidberg::PdParse;

use strict;

use Data::Dumper;
use IO::File;
use Storable qw/dclone/;
$Data::Dumper::Purity=1;
$Data::Dumper::Deparse=1;
$Data::Dumper::Indent=1;

sub pd_read_multi {
    my $self = shift;
    my $ref = {};
    for (@_) {
        $ref = $self->pd_merge($ref,$self->pd_read($_));
    }
    return $ref;
}

sub pd_read {
    my $self = shift;
    my $file = shift;
    my $fh = IO::File->new("< $file") or $self->print("Failed to fopen($file): $!\n"),return{};
    my $cont = join("",(<$fh>));
    $fh->close;
    my $VAR1;
    eval($cont);
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
    my $ref = shift @refs;
    foreach my $ding (@refs) {
        while (my ($k, $v) = each %{$ding}) {
            if (ref($v) && defined($ref->{$k})) {
                $ref->{$k} = $self->merge($ref->{$k}, $ding->{$k});     #recurs
            }
            else { $ref->{$k} = $v }
        }
    }
    return $ref;
}

1;
__END__
=head1 NAME

Zoidberg::PdParse - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Zoidberg::PdParse;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for Zoidberg::PdParse.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for Zoidberg::PdParse, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

root, E<lt>root@internal.cyberhqz.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002 by root

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

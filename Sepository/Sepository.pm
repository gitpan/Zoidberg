package Zoidberg::Sepository;

our $VERSION = 0.1;

use strict;
use base 'Zoidberg::Fish';

sub parse {
    my $self = shift;
    my $str = shift;
    my $nv = -d '_Inline';
    $str =~ s{^\\C}{};
    $str =~ s{^c[/\{\|\.]}{};
    $str =~ s{[\/\}\|\.]$}{};
    $str = "use Inline C => <<'ENDOFFUNKYINLINECODE';\nvoid stubfunc () { $str; }\nENDOFFUNKYINLINECODE\nstubfunc;";
    $self->parent->print(eval($str));
    if ($@) {
        $self->parent->{exec_error} = 1;
        $self->parent->print($@,"error");
    }
    unless ($nv) {
        $_='_Inline';
        $self->rdir;
    }
}

sub rdir {
    my $self = shift;
    -d && (map({
        -d && $self->rdir;
        -f && unlink;
    } glob"$_/*"),rmdir);
    -f && unlink
}


            
1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Zoidberg::Sepository - Inline:: glue

=head1 SYNOPSIS

  use Zoidberg::Sepository;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for Zoidberg::Sepository.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for Zoidberg::Sepository, created by h2xs. It looks like the
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

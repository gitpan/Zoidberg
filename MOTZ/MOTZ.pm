package fortune;

sub new {
    my $class = shift;
    my $self = {};
    $self->{filename} = shift;
    bless $self => $class;
}

sub pickQuote {
    my $self = shift;
    local $/ = "\%\n";
    open(FORTUNE,$self->{filename}) or return "X-Zoid: What? you've seen me naked?\n";
    my @quotes = (<FORTUNE>);
    close FORTUNE;
    my $pick = $quotes[int(rand(@quotes))];
    chomp $pick;
    $pick=~s{\%\s*$}{};
    return $pick;
}

package Zoidberg::MOTZ;

our $VERSION = '0.04';

use Data::Dumper;

use base 'Zoidberg::Fish';

sub init {
    my $self = shift;
    $self->{dir} = $self->{parent}->scan_dir($self->{config}{dir});
    $self->{files} = [map {$self->{config}{dir}."/".$_} @{$self->{dir}{files}}];
    $self->{files} = [map {fortune->new($_)} @{$self->{files}}];
    unless(@{$self->{files}}) { @{$self->{files}}[0] = fortune->new("") } # make stub
}

sub fortune {
    my $self = shift;
    $self->parent->print($self->pickFile->pickQuote, 'message');
}

sub pickFile {
    my $self = shift;
    my $id = int(rand(@{$self->{files}}));
    return $self->{files}[$id];
}

1;
__END__

=head1 NAME

Zoidberg::MOTZ - message of the zoid, replace fortune

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

ya know fortune ehh ?

=head1 METHODS

=head2 fortune()

  Return random quote

=head1 AUTHOR

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net.

=cut


package Zoidberg::Fish::MOTZ::fortune;

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
    my $i = int(rand(@quotes));
    $self->{id}=$i;
    my $pick = $quotes[$i];
    chomp $pick;
    $pick=~s{\%\s*$}{};
    return $pick;
}

    
package Zoidberg::Fish::MOTZ;

our $VERSION = '0.2';

use Data::Dumper;

use base 'Zoidberg::Fish';
use Zoidberg::FileRoutines qw/scan_dir/;

our @answer = (
		'yes', 'yes, Yes, YES !', 'no', 'NOOOooooo...',
		'maybe', 'how should I know such a thing !?',
		'Do you realize you\'re talking to a freaking eight ball !?',
		'ask Damian', 'it\'s all right with me',
		'ok', 'absolutely not', 'hmmm -- is that a sandwich you have there?',
		'MY, MY, YOU SHOULD BE MORE CAREFULL...', 'lp0 on fire!',
);

sub init {
    my $self = shift;
    $self->{dir} = scan_dir($self->{config}{dir});
    $self->{files} = [map {$self->{config}{dir}."/".$_} @{$self->{dir}{files}}];
    $self->{files} = [map {Zoidberg::Fish::MOTZ::fortune->new($_)} @{$self->{files}}];
    unless(@{$self->{files}}) { @{$self->{files}}[0] = Zoidberg::Fish::MOTZ::fortune->new("") } # make stub
    $self->register_event('message');
}

sub event {
    my $self = shift;
    eval{$self->{parent}->Brannigan->speak($_[1])};
}

sub fortune {
    my $self = shift;
    $self->parent->print($self->pickFile->pickQuote, 'message');
}

sub get {
    my $self = shift;
    my $f = $self->pickFile;
    my $q = $f->pickQuote;
    my $i = $f->{id};
    { msg => $q, date => time(), from => 'Zoidbee', id => $i }
}

sub eightball {
	my $self = shift;
	my $string = shift;
	my $int = int rand $#answer+1;
	if ($string eq 'disc') { $self->parent->print('The magic 7+1 ball says: '.$answer[$int]); }
    elsif ($string eq 'slet') { $self->parent->Buffer->set_string('egrep -ir "( fuck)|( shit)" /usr/src/linux/* | less'); }
	else { $self->parent->print('The magic eight ball says: '.$answer[$int]); }
}

sub pickFile {
    my $self = shift;
    my $id = int(rand(@{$self->{files}}));
    return $self->{files}[$id];
}

1;
__END__

=head1 NAME

Zoidberg::Fish::MOTZ - message of the zoid, replace fortune

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


package Zoidberg::Fish::Prompt;

our $VERSION = '0.41';

use strict;

use Zoidberg::Utils qw/read_data_file output/;
use Storable qw/dclone/; # hehe tooo late now, fix it later

use base 'Zoidberg::Fish';

sub init {
	my $self = shift;
    $self->{lookup} = read_data_file('ps1');
    $self->{children} = [];
    $self->append(@{dclone($self->{config}{prompt})});
}

sub dump {
    my $self = shift;
    output $$self{config};
}

sub children {
    my $self = shift;
    if (@_) { return $self->{children}[shift] }
    @{$self->{children}};
}

sub createChild {
    my $self = shift;
    return new Zoidberg::Fish::Prompt::string ($self,@_);
}

sub getLength {
    my $self = shift;
    my $tot;
    for ($self->children) {
        $tot+=$_->getLength;
    }
    $tot;
}

sub append {
    my $self = shift;
    for (@_) {
        if (ref($_) eq 'HASH') { # old style
            my $cont = [keys%{$_}]->[0];
            my $col = $_->{$cont};
            my $child = $self->createChild($cont,$col);
            push @{$self->{children}},$child;
        }
        else {
            push @{$self->{children}},$self->createChild($_);
        }
    }
}

sub stringify {
    my $self = shift;
    join("",map{$_->stringify}$self->children);
}

sub reset {
    my $self = shift;
    $self->{children} = [];
}


package Zoidberg::Fish::Prompt::string;

use Term::ANSIColor ();

sub new {
    my $class = shift;
    my $self = {parent=>shift,cont=>shift};
    $self->{lookup} = $self->{parent}{lookup};
    bless $self => $class;
    if (@_) {
        $self->color(shift);
    }
    $self = $self->init;
    return $self;
}

sub init {
    my $self = shift;
    if (ref($self->{cont})eq'ARRAY') {
        my $meta = delete $self->{cont};
        $self->{cont} = shift@{$meta};
        if (ref($meta->[0])eq'HASH') {
            $self->{meta}=shift@{$meta};
            if ($self->{meta}{color}) { $self->color($self->{meta}{color}) }
            if ($self->{meta}{maxlen}) { $self->{max_length} = $self->{meta}{maxlen} } else { $self->{max_length} = $self->{parent}{config}{max_length} }
            if (exists $self->{meta}{cache}) { $self->{cache_time} = $self->{meta}{cache} }
            else { $self->{cache_time} = 10 } # in seconds
        }
    }
    $self->stringify;
    if (($self->getLength > $self->{max_length})&&($self->{max_length})) {
        bless $self => 'Zoidberg::Fish::Prompt::string::scrolling';
    }
    $self;
}

sub replaceVar {
    my $self = shift;
    my $var = shift;
    unless (exists $self->{lookup}{$var}) { return $var }
    if (ref($self->{lookup}{$var}) eq 'CODE') {
        return $self->{lookup}{$var}->($self);
    }
    else {
        my $sub = eval $self->{lookup}{$var};
        if ((!$@)&&(ref($sub)eq'CODE')) {
            my $ret = $sub->();
            return $ret;
        }
        else {
            return $self->{lookup}{$var};
        }
    }
}

sub set {
    my $self = shift;
    $self->{cont} = shift;
}

sub isCode {
    my $self = shift;
    if (ref($self->{cont}) eq 'CODE') {
        return 1;
    }
    else {
        my $ret = eval $self->{cont};
        if (ref($ret)eq'CODE'and !$@) {
            $self->{cont} = $ret;
            return 1;
        }
    }
    return 0;
}

sub get {
    my $self = shift;
    $self->{cont};
}

sub getLength {
    my $self = shift;
    return length(stripAnsi($self->{laststring}));
}

sub stripAnsi {
    my $string = shift;
    $string =~ s{\e.*?m}{}g;
    return $string;
}

sub color {
    my $self = shift;
    if (@_) {
        $self->{color} = shift;
    }
    else {
        return $self->{color};
    }
}

sub cont {
    my $self = shift;
    return $self->{cont};
}

sub stringify {
    my $self = shift;
    if ([caller(2)]->[3]=~/condition$/||$self->condition) {
        return $self->_stringify;
    }
    $self->{laststring}="";
}

sub _stringify {
    my $self = shift;
    my $string;
    if ($self->{cache_time}>0 and defined $self->{laststring}) {
        if ($self->{cache_time}+$self->{_cachet}>time) {
            return $self->{laststring};
        }
        else { $self->{_cachet} = time }
    }
    if ($self->isCode) { $string = $self->cont->($self) }
    elsif (!ref($self->cont)) { $string = $self->cont }
    $string = $self->expandVars($string);
    $string = $self->colorify($string);
    $self->{laststring} = $string;
    return $self->{laststring};
}

sub condition {
    my $self = shift;
    unless (exists $self->{meta}{'if'}) { return 1 }
    my $code = eval($self->{meta}{if});
    if (ref($code)eq'CODE') {
        return $code->($self);
    }
    return $code;
}

sub colorify {
    my $self = shift;
    my $string = shift;
    if ($self->color) {
        $string = Term::ANSIColor::color($self->color).$string.Term::ANSIColor::color('reset');
    }
    return $string;
}

sub expandVars {
    my $self = shift;
    my $string = shift;
    $string =~ s{(\\[a-z])}{$self->replaceVar($1)}gie;
    return $string;
}

package Zoidberg::Fish::Prompt::string::scrolling;

use base 'Zoidberg::Fish::Prompt::string';

sub init {
    my $self = shift;
    $self->{i} = 0;
}

sub _stringify {
    my $self = shift;
    my $maxlen = $self->{max_length};
    my $string = Zoidberg::Fish::Prompt::string::stripAnsi(Zoidberg::Fish::Prompt::string::stringify($self));
    my $len = $self->getLength;
    if ($self->getLength <= $maxlen) { return Zoidberg::Fish::Prompt::string::stringify($self) }
    if ($self->{i} >= $self->getLength) { $self->{i} = 0 }
    if ($self->getLength > $maxlen) {
        $self->{i}++;
        my $pad = " "x$maxlen;
        $string = "$pad$string";
        $self->{laststring} = $string;
        $string = substr($string,$self->{i},$maxlen);
    }
    $self->{laststring} = $self->colorify($string);
}

1;
__END__

=head1 NAME

Zoidberg::Fish::Prompt - Modular prompt plugin for Zoidberg

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This module generates the prompt used by the
Buffer plugin. You can put any piece of perl code
in its config file to allow any function to output to
your prompt.

=head1 METHODS

=head2 stringify()

  Returns a string to use as prompt

=head2 getLength()

  Returns the length of the previously generated prompt.
  This is needed since the string might contain ANSI
  escape sequences, the length as returned by this sub
  is the length in printable chars

=head1 CONFIGURATION

  The prompt is defined in profile.pd
  A simple prompt definition might look like this: C<prompt => ['> ']>
  
  You can also use bash-like `PS1' escape sequences in the definition, for example: C<prompt => ['\w> ']>
  See the file ps1.pd for more details on the definition of escape sequences and bash-compatibility.
  
  The prompt definition is an array-reference, so it can contain multiple parts. These parts will be joined together into a string.
  For example: C<prompt => ['\w','>',' ']>
  
  You can supply hash references containing metadata in addition to the raw strings.
  For example: 
  prompt => [>
    ['\u',{color=>'magenta'}],
    '@',
    ['\h',{color=>'blue'}],
    ['(\L)',{color=>'yellow',if=>'sub{$self->stringify!~/-1/}'}],
    ['#',{color=>'yellow'}],
    ' ',
  ]
  These hashes can contain the following keys:
  
  color: This part of the prompt will be displayed in the given ANSI colour;
  maxlen: If the stringified result of this part is longer than $maxlen, the string will scroll from right to left;
  if: A piece of perl code that must return true in order for the part to be displayed. In this context, C<$self> means the current piece-of-string object. If the returnvalue is a CODE-reference, the returnvalue of that subref will determine the outcome;
  
=head1 AUTHOR

R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Copyright (c) 2002 Raoul L. Zwart. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net.

=cut

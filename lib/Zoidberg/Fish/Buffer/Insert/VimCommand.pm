package Zoidberg::Fish::Buffer::Insert::VimCommand;

our $VERSION = '0.42';

use Zoidberg::Fish::Buffer::Insert;
use Zoidberg::Fish::Buffer::Meta;

@Zoidberg::Fish::Buffer::Insert::VimCommand::ISA = qw{
	Zoidberg::Fish::Buffer::Insert 
	Zoidberg::Fish::Buffer::Meta
};

sub _switch_on {
    my $self = shift;
    $self->{_current_rec} = $self->_pack_record;
    $self->{pos} = [0, 0];
    $self->_part_reset;
    $self->{custom_prompt} = 1;
    $self->{prompt} = ':';
    $self->{prompt_lenght} = 1;
}

sub _switch_off {
    my $self = shift;
    $self->{custom_prompt} = 0;
    $self->_part_reset;
    $self->_unpack_record($self->{_current_rec});
}

sub k_esc {
    my $self = shift;
    $self->switch_modus('meta');
}

sub k_return {
    my $self = shift;
    my $line = $self->{fb}[0];
    $self->_parse_command($line);
    $self->switch_modus('meta');
}

sub k_tab {
    my $self = shift;

}

sub commands {
    my $self = shift;


}

sub _parse_command {
    my $self = shift;
    my $cmd = shift;
    if ($cmd =~ s/^([\s\d,]*)([a-z]+)//) {
        my $pre = $1;
        my $command = $2;
        my $sub = "c_$command";
        if ($self->can($sub)) { $self->$sub($pre,$command,$cmd) }
        else { print "\nCommand not yet understood: $command\n";sleep 1; }
    }
    else {
        print "\nCommand not yet understood: $cmd\n";
        sleep 1;
    }
}

sub c_q {
	my $self = shift;
	$self->reset;
	$self->{continu} = 0;
	$self->parent->exit;
	# FIXME last line should be enough
}

sub c_set {
    my $self = shift;
    my ($pre,$cmd,$arg) = @_;
    $arg =~ m/^\s*(.*)\s*$/;
    my $opt = $1;
    if ($self->{options}{$opt}) { $self->{options}{$opt} = 0 }
    else { $self->{options}{$opt} = 1 }
}
 
sub c_w {
    my $self = shift;
    my ($pre,$cmd,$arg) = @_;
    $arg =~ s{^\s*}{};
    my $r = ($pre=~/\d/)?$self->_parse_range($pre):[0,$#{$self->{_current_rec}[0]}];
    open(VIMSAVE,">$arg");
    for ($r->[0]..$r->[1]) {
        print VIMSAVE $self->{_current_rec}[0][$_]."\n";
    }
    close VIMSAVE;
    $self->respawn;
}

sub c_r {
    my $self = shift;
    my ($pre,$cmd,$arg) = @_;
    $arg =~ s{^\s*}{};
    unless(open(VIMREAD,$arg)) { print "Failed to open $arg for reading...";sleep 1; return }
    my @dus;
    while (<VIMREAD>) { chomp; push @dus, $_ }
    close VIMREAD;
    my ($x,$y) = @{$self->{_current_rec}[2]};
    my $fl = $self->{_current_rec}[0][$y];
    my $post = (length($fl)>$x+1)?substr($fl,$x,length($fl)-1):'';
    $dus[0].=substr($fl,0,$x);
    $dus[-1]=$dus[-1].$post;
    splice(@{$self->{_current_rec}[0]},$y,1,@dus);
    $self->respawn;
}

sub c_s {
    my $self = shift;
    my ($pre,$cmd,$arg) = @_;
    my $range = $self->_parse_range($pre);
    $arg =~ s/^\s*//;
    $arg = $cmd.$arg;
    for ($range->[0]..$range->[1]) {
        eval"\$self->{_current_rec}[0][$_]=~$arg";
    }
}

sub c_y {
    my $self = shift;
    $self->c_s(@_);
}

sub tr {
    my $self = shift;
    $self->c_s(@_);
}

sub _parse_range {
    my $self = shift;
    my $pre = shift;
    $pre =~ m/\s*(\d+)?\s*(\,)?\s*(\d+)?\s*$/;
    my ($a,$b,$c)=($1,$2,$3);
    my $range;
    if ($a&&$b&&$c) {
        $range->[0] = $a;
        $range->[1] = $c;
    }
    elsif (!$b) {
        $range->[0] = $range->[1] = $a;
    }
    else {
        if ($a) {
            $range->[0] = $a;
            $range->[1] = $#{$self->{_current_rec}[0]};
        }
        elsif ($c) {
            $range->[0] = $self->{_current_rec}[2][1];
            $range->[1] = $c;
        }
    }
    if ($range->[0] < 0) { $range->[0] = 0 }
    elsif ($range->[0] > $#{$self->{_current_rec}[0]}) { $range->[0] = $#{$self->{_current_rec}[0]} }
    if ($range->[1] < 0) { $range->[1] = 0 }
    elsif ($range->[1] > $#{$self->{_current_rec}[0]}) { $range->[1] = $#{$self->{_current_rec}[0]} }
    $range;
}

1;

package Zoidberg::Eval;

our $VERSION = '0.3a';

use strict;
use vars qw/$AUTOLOAD/;

use Data::Dumper;
use File::Glob ':glob';
use Zoidberg::Error;
use Zoidberg::FileRoutines qw/:exec_scope is_exec_in_path/;
use Zoidberg::Shell qw/:exec_scope/;

our @PATH;
our $DEBUG = 0;
export(\@PATH => 'PATH');

$| = 1;

sub _new {
	my $class = shift;
	my $self = {};
	$self->{zoid} = shift; # this will be $self for eval blocks
	bless $self, $class;
}

sub _eval_block {
	my ($self, $block) = @_;
	my $meta = shift @{$block};
	my $context = $meta->{context};
	
	my $orig_ref = $ENV{ZOIDREF};
	$ENV{ZOIDREF} = $self;

	eval {
		# TODO check plugin contexts
		if ($self->can('_do_'.lc($context))) {
			my $sub = '_do_'.lc($context);
			print "debug: going to call sub: $sub,\nblock: ", Dumper $block if $DEBUG;
			$self->$sub($block, $meta);
		}
		else { error qq/No handler defined for context $context\n/ }
	};
	
	$ENV{ZOIDREF} = $orig_ref if defined $orig_ref;

	if ($@) {
		$self->{exec_error} = $@;
		$self->{zoid}->print_error($@);
	}
	else { undef $self->{exec_error} }

}

=begin comment

The  nice  and simple rule given above: `expand a wildcard pattern into
the list of matching pathnames' was the original  Unix  definition. It
allowed one to have patterns that expand into an empty list, as in
xv -wait 0 *.gif *.jpg where  perhaps  no  *.gif files are present 
(and this is not an error). However, POSIX requires that a wildcard 
pattern is left unchanged  when it  is  syntactically  incorrect,  
or the list of matching pathnames is empty.  With bash one can force  
the  classical  behaviour  by  setting allow_null_glob_expansion=true.

So the setting allow_null_glob_expansion should switch of GLOB_NOCHECK

=end comment

=cut

sub _do_sh {
	my ($self, $block, $meta) = @_;
	my @r;

	# path expansion
	unless ($self->{zoid}{settings}{noglob}) {
		my $glob_opts = GLOB_MARK|GLOB_TILDE|GLOB_BRACE|GLOB_QUOTE;
		$glob_opts |= GLOB_NOCHECK unless $self->{zoid}{settings}{allow_null_glob_expansion};
		@r = map { /^['"](.*)['"]$/s ? $1 : bsd_glob($_, $glob_opts) } @{$block} ;
	}
	else { @r = map { /^['"](.*)['"]$/s ? $1 : $_ } @{$block} }
	
	print "debug: going to exec : ", Dumper \@r if $DEBUG;

	_check_exec($r[0]) unless $meta->{_is_checked};

	$self->{zoid}{_} = $r[-1]; # useless in fork (?)
	if ($self->{zoid}->{round_up}) { system(@r); }
	else { exec {$r[0]} @r; }
}

sub _check_exec {
	# arg 0 is executable when this sub doesn't die
	if ($_[0] =~ m|/|) {
		error $_[0].': No such file or directory' unless -e $_[0];
		error $_[0].': is a directory' if -d $_[0];
		error $_[0].': Permission denied' unless -x $_[0];
	}
	elsif (! is_exec_in_path($_[0])) { error $_[0].': command not found' }
}

sub _do_cmd {
	my ($self, $block, $meta) = @_;
	my $cmd = shift @{$block};
	error qq(No such command: $cmd\n) unless $self->_is_cmd($cmd);
	return $self->{zoid}{commands}{$cmd}->(@{$block});
}

sub _is_cmd { exists $_[0]->{zoid}{commands}{$_[1]} }

sub _do_perl {
	my ($_Eval, $_Block, $_Meta) = @_;
	my $_Code = $_Block->[0];
	$_Code = $_Eval->_dezoidify($_Code) if $_Meta->{dezoidify};
	$_Code = $_Eval->_parse_opts($_Code, $_Meta->{opts}) if $_Meta->{opts};
	print "debug: going to eval perl code: -->no strict; $_Code<--\n"  if $DEBUG;

	my $self = $_Eval->{zoid};
	$_ = $self->{_};
	
	eval('no strict; '.$_Code); # TODo, what about the return value ?  # FIXME make strict an option
        die if $@; # should we check $! / $? / $^E here ?
	
        $self->{_} = $_;
	 print "\n"; # ugly hack
}

our $_Zoid_gram = {
# The original regexp:
# ((?<![\\w\\}\\)\\]])->|\\xA3)([\\{]?\\w+[\\}]?)
	esc => qr/[\w\}\)\]]/,
	tokens => [
		[ qr/->/,   'ARR' ], # ARRow
		[ qr/\xA3/, 'MCH' ], # Magic CHar
	],
	nests => {},
	no_esc_rm => 1,
};

sub _dezoidify {
	my ($self, $code) = @_;
	my $p = $self->{zoid}{StringParser};
	$p->set($_Zoid_gram, $code);
	my ($n_code, $block, $token, $prev_token, $thing);
	while ($p->more) { 
		$prev_token = $token;
		($block, $token) = $p->get;
		#print "code is -->$n_code<-- prev token -->$prev_token<--\ngot block -->$block<-- token -->$token<--\n";
 
		unless (defined $n_code) { $n_code = $block; next }
		$n_code .= '->'.$block and next unless ($thing) = ($block =~ /^(\{?\w+\}?)/);
		#print "thing -->$thing<--\n";

		if ($self->{zoid}{settings}{naked_zoid} && ($prev_token ne 'MCH') ) { $n_code .= '$self->'.$block }
		elsif (grep {$_ eq $thing} @{$self->{zoid}->list_clothes}) { $n_code .= '$self->'.$block }
		elsif ($thing =~ m|^\{|) { $n_code .= '$self->{vars}'.$block } # is {vars} still usefull ?
		else { 
			$block =~ s/^(\w+)/\$self->object('$1')/;
			$n_code .= $block;
		}
	}
	return $n_code;
}

sub _parse_opts { # parse switches
	my ($self, $string, $opts) = @_;

	# TODO if in pipeline set 'n' as defult unless 'N'

	if ($opts =~ m/g/) { $string = "\nwhile (<STDIN>) {\n\tif (eval {".$string."}) { print \$_; }\n}"; }
	elsif ($opts =~ m/p/) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n\tprint \$_\n}"; }
	elsif ($opts =~ m/n/) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n}"; }

#	if ($opts =~ m/b(\d+)/) {
#		$string = qq{ \$self->print(
#	Benchmark::timestr(Benchmark::timethis($1, sub{
#		$string
#	},'','none'))) };
#	}

	return $string;
}

sub AUTOLOAD {
	## Code inspired by Shell.pm -- but rewrote it
	
	my $self;
	if (ref($_[0]) eq 'Zoidberg::Eval') { $self = shift }
	else { $self = $ENV{ZOIDREF} }

	my @args = @_;
	my $cmd = (split/::/,$AUTOLOAD)[-1];

	return undef if $cmd eq 'DESTROY';
	print "debug: autoload got command: $cmd\n" if $DEBUG;

	if ($self->_is_cmd($cmd)) { $self->_do_cmd([$cmd, @args]) }
	else { # system
		_check_exec($cmd);
		open CMD, '-|', $cmd, @_;
		my @ret = (<CMD>);
		close CMD;
		$self->{exec_error} = $?;
		if (wantarray) { return map {chomp; $_} @ret; }
		else { return join('',@ret); }
	}
}

1;

__END__


=head1 NAME

Zoidberg::Eval

=head1 DESCRIPTION

This module is intended for internal use only.
See L<Zoidberg::ZoidParse>.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut


package Zoidberg::Intel;

our $VERSION = '0.1';

use Zoidberg::StringParse;
use base 'Zoidberg::Fish';

use strict;
use Data::Dumper;
use Devel::Symdump;
use Storable qw/dclone/;

sub init { #use: system exec file zoid perl hist
	my $self = shift;
	$self->{StringParser} = Zoidberg::StringParse->new($self->parent->{grammar}, 'space_gram');
	$self->{default} = {
		'ZOID'		=> [qw/c_zoid c_perl/],
		'DEFAULT'	=> [qw/c_hist/],
	};
}

sub StringParser { return $_[0]->{StringParser}; }

sub expand {
	# args: fb_string, i_feel_lucky_bit
	# returns (message, fb, poss)
	my $self = shift;
	my $string = shift;
	my $i_feel_lucky_bit = shift; # TODO use this bit
	$self->flush;
	my $tree = $self->StringParser->parse($string, 'pipe_gram', 1, 1);
	#print "debug :".Dumper($tree);
	# <VUNZIG>
	$self->{old_block} = $tree->[-1][0];
	$self->StringParser->{tree} = [ [$tree->[-1][0], '', ''] ];
	$self->StringParser->parse_rules($self->parent->{grammar}{pipe_gram}{default_context}, 1);
	$self->{block} = $self->StringParser->{tree}[0][0];
	my $context = $self->StringParser->{tree}[0][2];
	# </VUNZIG>
	#print "debug: expand: block: --$self->{block}-- context: --$context--\n";

	# neem overlap
	# TODO

	$self->parse($self->empty_set, $context);

	# <TODO>
	$self->{block} = $self->{old_block};
	# </TODO>

	@{$self->{poss}} = grep {@{$_->{poss}}} @{$self->{poss}};
	#print "debug : ".Dumper($self->{poss});

	if ($#{$self->{poss}} == 0) {
		my $set = shift @{$self->{poss}};
		if ($#{$set->{poss}} == 0) {
			my $new_arg = $set->{poss}->[0].$set->{postf};
			# print "debug: recombine: old_arg: $set->{old_arg} new_arg: $new_arg\n";
			$self->{block} =~ s/(?$set->{reg_opt}:\Q$set->{old_arg}\E)$/$new_arg/;
			return ($self->{message}, $self->{block}, []);
		}
		else {
			my $new_arg = $set->{poss}->[0];
			for (@{$set->{poss}}[1..$#{$set->{poss}}]) {
				unless ($_ =~ m/^(?$set->{reg_opt}:\Q$new_arg\E)/) {
					while ($_ !~ m/^(?$set->{reg_opt}:\Q$new_arg\E)/) {
						$new_arg = substr($new_arg, 0, length($new_arg)-1);
					}
				}
			}
			#print "debug: mult-recombine: old_arg:$set->{old_arg} new_arg: $new_arg\n";
			if ((defined $new_arg) && ($new_arg =~ /^(?$set->{reg_opt}:$set->{arg})/)) {
				$self->{block} =~ s/\Q$set->{old_arg}\E$/$new_arg/;
			}
			return ($self->{message}, $self->{block}, @{$set->{poss}} ? $set->{poss} : []);
		}
	}
	else { return ($self->{message}, $self->{block}, []); } # temp stub

	# map overlap & recombine tree
	# TODO
}

sub expand_files {
	my $self = shift;
	my $string = shift(@_);
	$self->flush;
	my $set = $self->empty_set;
	$set->{old_arg} = $string.'$';
	$set->{no_default} = 1;
	$self->parse($set, 'FILE');
	#print "debug: ".Dumper($self->{poss});
	my @results = map {
		my $set = $_;
		$set->{old_arg} =~ s/\$?$//;
		map {
			my $ding = $string;
			$ding =~ s/\Q$set->{old_arg}\E$/$_/;
			$ding;
		} @{$set->{poss}};
	} @{$self->{poss}};
	#print "debug: ".join('--', @results)."\n";
	if (@results) { return [@results]; }
	else { return [$string]; }
}

sub empty_set {
	return {
		'poss'	=> [],		# array of possebilities
		'postf'	=> '',		# postfix for single match (almost always ' ' if any)
		'arg'	=> '',		# regex matched by poss
		'old_arg'	=> '',	# arg before glob parsing
		'reg_opt'	=> '',	# regex switched (almost always 'i' if any)
	};
}

sub flush {
	my $self = shift;
	$self->{block} = '';		# modified block
	$self->{message} = '';		# message -- displayed above poss
	$self->{old_block} = '';	# non modified block
	$self->{poss} = [];		# sets of poss
}

sub parse {
	my $self = shift; #print "debug parse got: --".join('--',@_)."--\n";
	my $set = shift;
	my $context = shift;
	my @try = ();

	# TODO specials (?)
	if ($self->parent->{grammar}{context}{$context} && $self->parent->{grammar}{context}{$context}[1]) {
		@try = ('parent->'.$self->parent->{grammar}{context}{$context}[1]);
	}
	elsif ($self->{default}{$context}) { @try = @{$self->{default}{$context}}; }
	elsif ($self->can('c_'.lc($context))) { @try = ('c_'.lc($context)); }
	# TODO allow for arguments

	for (@try) {
		eval ('$self->'.$_.'(dclone($set), $self->{block}, $self)');
		if ( $self->we_have_a_winner ) { last; }
	}

	unless ($self->we_have_a_winner) {
		if (@_) { $self->parse($set, shift @_); } # recurs
		elsif (($context ne 'DEFAULT') && !$set->{no_default}) { 
			$self->parse($set, 'DEFAULT'); # recurs
		}
	}

}

sub set_arg { # checks for globing and handles malafide regexes
	my $self = shift;
	my ($set, $old_arg) = @_;
	$set->{arg} = $old_arg;
	$set->{old_arg} = $old_arg;
	if ($self->{parent}->{core}{no_regex}) { #regex to glob -- TODO put this in a gramar
		$set->{arg} =~ s/([\*\?])/\.$1/g;
	}
	elsif (!$self->{parent}->{core}{strict_regex}) { #some regex to glob -- TODO put this in a gramar
		$set->{arg} =~ s/(?:^|(?<=[\w\s]))([\*\?])/\.$1/g;
	}
	$set->{arg} =~ s/^\^?/\^/;
	eval {  #sanity check
		my $test = 'Alexej Fedorowitsj was the third son of Fedor Pawlowitsj Karamazow, ...';
		$test =~ m/$set->{arg}/;
	} ;
	if ($@) {
		$self->parent->print("\n".$@);
		return undef;
	}
	else { return $set; }
}

sub we_have_a_winner {
	my $self = shift;
	return (@{$self->{poss}} && (grep {@{$_->{poss}}} @{$self->{poss}}) ) ? 1 : 0;
}

sub escape_all {
	my $string = $_[1];
	$string =~ s/([ \`\&\"\'\(\)\{\}\[\]\|\>\<\*\?\%\$\!\~])/\\$1/g;
	return $string;
}

sub cut_double { # verwijder dubbelen
	my $self = shift;
	my $set = shift;
	my @dus = ();
	foreach my $ding (@{$set->{poss}}) { unless ( grep {$_ eq $ding} @dus ) { push @dus, $ding }; }
	$set->{poss} = [@dus];
	return $set;
}

sub add_poss {
	my $self = shift;
	my $set = shift;
	push @{$self->{poss}}, $set;
}

sub c_system {
	my $self = shift;
	my $set = shift;
	unless ($set->{arg}) {
		my @tree = @{ $self->StringParser->parse($self->{block}, 'space_gram', 1) };
		$set = $self->set_arg($set, $tree[-1][0]);
		if (defined $set) { $set->{space_blocks} = $#tree; }
	}
	if (defined $set) {
		if ($set->{space_blocks} > 0) { $self->parse($set, 'FILE'); }
		else { $self->parse($set, 'PATH', 'FILE'); }
	}
}

sub c_path {
	my $self = shift;
	my $set = shift;
	unless ($set->{arg}) {
		my @tree = @{ $self->StringParser->parse($self->{block}, 'space_gram', 1) };
		$set = $self->set_arg($set, $tree[-1][0]);
		if (defined $set) { $set->{space_blocks} = $#tree; }
	}
	if (defined $set) {
		push @{$set->{poss}}, sort grep /$set->{arg}/, @{$self->parent->list_path};
		$set->{postf} = ' ';
		push @{$self->{poss}}, $set;
	}
}

sub c_file {
	my $self = shift;
	my $set = shift;
	unless ($set->{old_arg}) {
		my @tree = @{ $self->StringParser->parse($self->{block}, 'space_gram', 1) };
		$set->{old_arg} = $tree[-1][0]; # no checking done here on purpose
	}
	$set->{old_arg} =~ /^(.*(?<!\\)\/)*(.*)$/;
	#print "debug: file: dir: --$1-- tail: --$2--\n";
	if ( defined ($set = $self->set_arg($set, $2)) ) { #print "debug: file: arg: $set->{arg}\n";
 		my $dir = $self->parent->scan_dir($1);
		#print "debug: dir: ".Dumper($dir);
		push @{$set->{poss}}, map {$self->escape_all($_)} sort grep /$set->{arg}/, map {$_."/"} @{$dir->{dirs}};
		push @{$set->{poss}}, map {$self->escape_all($_)} sort grep /$set->{arg}/, @{$dir->{files}};
		$set->{postf} = '';
		push @{$self->{poss}}, $set;
	}
}

sub c_zoid {
	my $self = shift;
	my $set = shift;

	unless ($set->{arg}) {
		my @tree = @{ $self->StringParser->parse($self->{block}, 'space_gram', 1) };
		$tree[-1][0] =~ s/^(\s*->)//;
		$set->{pref} = $1 || '';
		$set = $self->set_arg($set, $tree[-1][0]);
		if (defined $set) { $set->{space_blocks} = $#tree; }
	}

	if ((defined $set) && ($set->{pref} =~ /^\s*->/)) { #print "debug: going to try zoid\n";
		my $tail = $set->{arg};
		$tail =~ s/^\^?(.+->)*//;
		my $name = $1;
		if ($tail =~ /^(([\[\{].*?[\]\}])*)(.*)$/) {
			$name .= $1;
			$tail = $3;
		}
		if ($set->{pref}) {
			$set->{pref} .= $name;
			$name = '$self->parent->'.$name;
		}
		else {
			$name =~ /^(.+?)->(.*)/;
			my ($obj, $rest) = ($1, $2);
			$set->{pref} = $1.'->'.$2;
			$obj =~ s/^\s*//;
			($obj) = grep {/^$obj$/i} @{$self->parent->list_objects};
			$name = "\$self->parent->\{objects\}\{$obj\}->$rest";
		}
		$name =~ s/(\s*->)?$//;
		$name =~ s/\\\[(\d*)\\\]/[$1]/g;
		#print "debug: zoid: name: $name, tail: $tail, pref: $set->{pref}\n";

		my $ding = eval($name);
		unless (ref($ding)) { # $ding is scalar
			push @{$set->{poss}}, $ding;
			$set->{pref} = "";
		}
		elsif (ref($ding) eq 'HASH') { push @{$set->{poss}}, sort grep {/^$tail/} map {'{'.$_.'}'} keys %{$ding}; }
		elsif (ref($ding) eq 'ARRAY') {
			my @numbers = ();
			for (0..$#{$ding}) {push @numbers, $_; }
			push @{$set->{poss}}, map {s/([\[\]])/\\$1/g;$_} grep {/^$tail/} map {'['.$_.']'} @numbers; # second map to get escaping right
		}
		elsif (ref($ding) eq 'CODE') { $self->{message} = "\'$name\' is a CODE reference"; } # do nothing (?)
		else { # $ding is object
			my $object = eval($name);
			my $class = ref($object);
			if ($object && $class) { # print "\ndebug: object: $object -- class: $class \n";
				push @{$set->{poss}}, sort grep {/^$tail/i} map{"{$_}"}keys %{$object};
				push @{$set->{poss}}, sort grep {/^$tail/i} map {s/^(.+\:\:)*//g; $_} (Devel::Symdump->new($class)->functions);
			}
		}

		push @{$self->{poss}}, $set;
	}

}

sub c_perl {
	my $self = shift;

	# TODO set_arg
	my $block = $self->{block};
	if ($self->{arg} =~ /^(\\?\&|\w)/) {
		my @subs = ();
		$block =~ s/sub\s+(\w+)/push @subs, $1;/ge;
		if ($self->{arg} =~ s/^(\\?\&)//) {
			$self->{pref} = $1;
			push @{$self->{poss}}, grep {/$self->{arg}/} @subs;
		}
		else { push @{$self->{poss}}, grep {/$self->{arg}/} (@{$self->{parent}->{grammar}{perl_functions}}, @subs); }
	}
	elsif ($self->{arg} =~ s/^(\\?[\$\@\%])//) {
		$self->{pref} = $1;
		if ($self->{pref} eq '%') {
			my @hashes = ();
			$block =~ s/\%(\w+)/push @hashes, $1;/ge;
			push @{$self->{poss}}, grep {/$self->{arg}/} @hashes;
		}
		elsif ($self->{pref} eq '@') {
			my @arrays = ();
			$block =~ s/\@(\w+)/push @arrays, $1;/ge;
			push @{$self->{poss}}, grep {/$self->{arg}/} @arrays;
		}
		else {	# $sigil eq '$'
			my @vars = ();
			$block =~ s/\$(\w+)/push @vars, $1;/ge;
			push @{$self->{poss}}, grep {/$self->{arg}/} @vars;
			my @hashes = ();
			$block =~ s/\%(\w+)/push @hashes, $1;/ge;
			push @{$self->{poss}}, grep {/$self->{arg}/} @hashes;
			my @arrays = ();
			$block =~ s/\@(\w+)/push @arrays, $1;/ge;
			push @{$self->{poss}}, grep {/$self->{arg}/} @arrays;
		}
	}
}

sub c_hist { # print "debug: hist expand\n";
	my $self = shift;
	my $set = shift;
	if ( defined ($set = $self->set_arg($set, $self->{old_block})) ) {
		push @{$set->{poss}}, sort grep {/$set->{arg}/} @{$self->parent->History->list_hist};
		# TODO more intelligent history matching ?
		$set = $self->cut_double($set);
		push @{$self->{poss}}, $set;
	}
}

1;
__END__

=head1 NAME

Zoidberg::Intel - Zoidberg module handling tab expansion and globbing

=head1 SYNOPSIS

This module is a Zoidberg plugin,
see Zoidberg::Fish for details.

=head1 DESCRIPTION

This class provides intelligence for tab-expansion
and similar functions. It is very dynamic structured.

=head2 EXPORT

None by default.

=head1 METHODS

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net.

=cut


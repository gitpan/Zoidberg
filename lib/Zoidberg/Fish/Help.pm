
package Zoidberg::Fish::Help;

use strict;
use Zoidberg::Utils;
use base 'Zoidberg::Fish';

my @topics = qw/about command/;

sub help {
	my $self = shift;
	unless (@_) {
		output << 'EOH';
Usage:
	> help about
	  prints about text
	> help some_cmd
	  outputs help about this command either
	  if it is a built in command
	
	see also man zoiduser
EOH
		return;
	}

	my $sub = (grep {$_[0] eq $_} @topics) ? shift : 'command' ;
	return $self->$sub(@_);
}

sub command {
	my ($self, @cmd) = @_;
	
	# TODO check aliases
	my $block = $$self{parent}->parse_block([@cmd], undef, 'PRETEND');
	my $context = $$block[0]{context};
	if (uc($context) eq 'PERL') {
		output "'$cmd[0]' seems to be a perl command, try:\n  > perldoc -f $cmd[0]";
	}
	elsif (uc($context) eq 'CMD' or !$context && exists $$self{parent}{commands}{$cmd[0]}) {
		output "$cmd[0] is a built in command";
		my $tag = Zoidberg::DispatchTable::tag($$self{parent}{commands}, $cmd[0]);
		output "but there is no information available about it"
			and return unless $tag;
		output "it belongs to the $tag plugin";
		my $file = tied( %{$$self{parent}{objects}} )->[1]{$tag}{module};
		output "\nno other help available" and return unless $file;
		$file =~ s/::/\//g;
		$file .= '.pm';
		$self->_grep_cmd_pod($file, @cmd);
	}
	elsif (uc($context) eq 'SH' or !$context) {
		output "'$cmd[0]' seems to be a system command, try:\n  > man $cmd[0]";
	}
	else { todo "Help functionality for context: $context" }
}
	
sub _grep_cmd_pod {
	my ($self, $file, $cmd) = @_;

	if (exists $INC{$file}) { $file = $INC{$file} }
	else { ($file) = grep {-e "$_/$file"} @INC }

	output "\nno other help available" and return unless -e $file;
	
	open POD, $file || error "Could not read $file";

	while (<POD>) { last if /^=head\d+\s+commands/i }

	my ($help, $p, $o) = ('', 0, 0);
	while (<POD>) {
		if (/^=item\s+$cmd/) { $p = 1 }
		elsif (/^=over/ && $p) { $o++ }
		elsif (/^=back/ && $p) { $o-- }
		elsif (/^=(item|cut)/ && !$o) { last }

		$help .= $_ if $p;
	}
	close POD;

	$help =~ s/^\s+|\s+$//g;
	output "\n".$help;
}

sub about {
		output << "EOH";
This is the Zoidberg shell version $Zoidberg::VERSION

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

http://zoidberg.sourceforge.net
EOH
}

__END__

=head1 NAME

... - simple module

=head1 SYNOPSIS

simple code example

	use Simple::Module;

	my $smod = Simple::Module->new

=head1 DESCRIPTION

descriptve text

=head1 EXPORT

None by default.

=head1 COMMANDS

=over 4

=item help [I<subject>|I<command>]

Prints help output on a I<subject> or a (built-in) I<command>.

=back

=head1 AUTHOR

Jaap Karssenberg (Pardus) E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

=cut


package Zoidberg::Shell;

use strict;
use vars qw/$AUTOLOAD $SHELL/;
use Carp;
use Env ();
use Exporter::Inheritor;
use Zoidberg::Error;

our $VERSION = '0.3b';

our @ISA = qw/Exporter::Inheritor/;
our @EXPORT = qw/AUTOLOAD $SHELL/;
our @EXPORT_OK = qw/export unexport AUTOLOAD $SHELL/;
our %EXPORT_TAGS = (
	exec_scope => [qw/export unexport/],
);

sub _bootstrap { our $SHELL = Zoidberg::Shell->_new unless $SHELL }

##########################
#### Object interface ####
##########################

sub _new {
	my $class = shift;
	my $self = {};
	bless $self, $class;

	if (ref $ENV{ZOIDREF}) { $self->{zoid} = $ENV{ZOIDREF}->{zoid} }
	else { todo 'autostart ipc' }

	return $self;
}

sub cmd {
	my $self = shift;
	my @words = $self->{zoid}->_check_aliases(@_);
	@words = grep {$_} @words; # filter out empty fields
	my $context = exists($self->{zoid}{commands}{$words[0]})
		? 'CMD'
		: 'SH' ;
	$self->{zoid}->do_job(
		{ string => join(' ', @words), foreground => 1 },
		[ [$context, @words] ] );
}

sub system { todo }
sub perl { todo }
sub eval { todo }

#########################
#### Non-OO routines ####
#########################

sub export {
	my %vars;
	if (ref $_[0] eq 'HASH') { %vars = %{$_[0]} }
	else { %vars = reverse @_ } # from ref => name to name => ref
	for (keys %vars) {
		my ($name, $type) = ($_, ref $vars{$_});
		if ($type eq 'SCALAR') { 
			my $copy = ${$vars{$name}};
			tie ${$vars{$name}}, 'Env', $name;
			${$vars{$name}} = $copy if defined $copy;
		}
		elsif ($type eq 'ARRAY') {
			my @copy = @{$vars{$name}};
			tie @{$vars{$name}}, 'Env::Array', $name;
			@{$vars{$name}} = @copy if @copy;
		}
		else { croak "Can't export data type: $type" }
	}
}

sub unexport { todo }

sub AUTOLOAD {
	return if $AUTOLOAD =~ /::DESTROY$/;
	todo "should this work like Zoidberg::Eval::AUTOLOAD ?";
}

###################
#### internals ####
###################



1;

__END__

=head1 NAME

Zoidberg::Shell - an interface to the Zoidberg shell

=head1 SYNOPSIS

	use Zoidberg::Shell;
	
	$SHELL->cmd(qw{cd /usr});

=head1 DESCRIPTION

This module is intended to let perl scripts interface to the Zoidberg shell the easy way. 
The most important usage for this is to write 'source scripts' for the Zoidberg shell which can 
use and change the shell environment like /.*sh/ scripts do with /.*sh/ environments.

=head1 EXPORT

By default a variable $SHELL is exported, this variable gives OO access to the current Zoidberg shell
if any.

FIXME

=head1 METHODS

=head2 Exported methods

=over 4

=item C<export()>

Like the 'export' built-in for /.*sh/ environments.

FIXME

=item C<unexport()>

TODO

=back

=head2 Object methods

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut

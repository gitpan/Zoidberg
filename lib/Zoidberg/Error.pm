
package Zoidberg::Error;

our $VERSION = '0.3a_pre1';

use strict;
use Carp;
require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw/error bug todo/;

use overload 
	'""' => \&stringify,
	'eq' => sub { return $_[0] };

# ################ #
# Exported methods #
# ################ #

our %_caller = (
	'package' => 0,
	'file'    => 1,
	'line'    => 2,
); # more ?

sub error {
	my @caller = caller;
	my %error = map {($_ => $caller[$_caller{$_}])} keys %_caller;

	die PROPAGATE($@, @error{qw/file line/}) if $@ && !@_; # make it work more like die

	while (@_) {
		my $ding = shift;
		my $t = ref $ding;
		unless ($t) { $error{string} .= $ding }
		elsif ($t eq 'HASH' || $t eq __PACKAGE__) { %error = ( %error, %{$ding} ) }
		else { croak 'Argument has wrong data type' }
	}
	
	$error{string} = $error{is_bug}
		? 'This is a bug'
		: $error{is_todo} 
			? 'Something TODO here'
			: 'Error'
		unless $error{string};

	{
		no strict 'refs';
		$error{debug}++ if ${ $error{package}.'::DEBUG' };
	}

	die bless \%error, __PACKAGE__;
}

sub bug {
	unshift @_, { is_bug => 1 };
	goto \&error;
}

sub todo {
	unshift @_, { is_todo => 1 };
	goto \&error;
}

# ############## #
# Object methods #
# ############## #

sub stringify {
	# TODO verbosity optie
	no warnings; # lots of stupid warnings here (due to 'overload' ?)
	my $self = shift;
	my %opt = @_;
	my $string;
	if ($opt{format} eq 'gnu') {
		# TODO output cmd name + input line number
		$string = join(': ', map {$self->{$_}} qw/package line string/) ."\n";
	}
	else { $string = $self->_perl_string }
	for (qw/bug todo/) { $string = uc($_) .': '.$string if $self->{'is_'.$_} }
	return $string;
}

sub _perl_string {
	my $self = shift;
	my $string = $self->{string};
	$string .= qq# at $self->{file} line $self->{line}\n# unless $string =~ /\n$/;
	for (@{$self->{propagated}}) { $string = PROPAGATE($string, $_->{file}, $_->{line}) }
	return $string;
}

sub debug { $_[0]->{debug} }

sub PROPAGATE { # see perldoc -f die
	my ($self, $file, $line) = @_;
	if (ref($self) eq __PACKAGE__) {
		$self->{propagated} = [] unless $self->{propagated};
		push @{$self->{propagated}}, {
			'file' => $file,
			'line' => $line,
		};
	}
	elsif ($self->can('PROPAGATE')) { $self = $self->PROPAGATE }
	else { $self .= "\t...propagated at $file line $line\n" }
	return $self;
}


1;

__END__

=head1 NAME

Zoidberg::Error - error handling module

=head1 SYNOPSIS

	use Zoidberg::Error;
	
	sub some_command {
		error("Wrong number of arguments")
			unless scalar(@_) == 3;
		# do stuff
	}

	# this raises an object oriented exception

=head1 DESCRIPTION

This library supplies the methods to replace C<die()>.
These methods raise an exception but passing a object containing both the error string
and caller information. Thus, when the exception is caught, more subtle error messages can be produced
depending on for example verbosity settings.

=head1 TODO 

More tracing stuff:
We could use for example an environment variable to control
verbosity, see C<caller()>. Or on global in the caller package.

Carp and croak like funtions (use other names to avoid confusion)

Maybe a function that traces till the top level input line is found ?
This is very croak like, but just a little different. Possibly this 
needs an oo interface, or an global in the caller package ...

=head1 EXPORT

By default C<error()>, C<bug()> and C<todo()>.

=head1 METHODS

=head2 Exported methods

=over 4

=item C<error($error, ..)>

Raises an exception which passes on C<\%error>.

=item C<bug($error, ..)>

Like C<error()>, but with C<is_bug> field set.

=item C<todo($error, ..)>

Like C<error()>, but with C<is_todo> field set.

=back

=head2 Object methods

=over 4

=item C<stringify(%opts)>

Returns an error string.

Known options:

=over 4

=item format

Types 'gnu' and 'perl' are supported. 
The format 'perl' is the default.

=back

=item C<PROPAGATE($file, $line)>

Is automaticly called by C<die()> when you use for example:

	use Zoidberg::Error;

	eval { error 'test' }
	die if $@; # die is called without explicit argument !

See L<perlfunc/die>.

=back

=head1 ATTRIBUTES

The exception raised can have the folowing attributes:

=over 4

=item string

Original error string.

=item package

Calling package.

=item file

Source file where the exception was raised.

=item line

Line in source file where the exception was raised.

=item is_bug

This exception should never happen, if it does this is considered a bug.

=item is_todo

This exception is raised because some feature isn't yet implemented.

=item propagated

Array of hashes containg information about files and line numbers where
this error was propagated, see L</PROPAGATE>.

=back

=head2 Overloading

When the methods are given a hash reference as one of there arguments
this hash overloads the default values of C<%error>. Thus it is possible to fake
for example the calling package, or add meta data to an exception.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>,
L<http://www.gnu.org/prep/standards_15.html#SEC15>

=cut


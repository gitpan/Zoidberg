=pod

=head1 NAME

Zoidberg::Config - hardcoded configuration

=head1 SYNOPSIS

	my %settings = %Zoidberg::Config::settings;

=head1 DESCRIPTION

B<This modules is intended for internal use only.>

This package contains some hardcoded configuration, some of it included
at compile time. Normal configuration data is included in external data files,
this module holds info on where to find those data files.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut

package Zoidberg::Config;

our $VERSION = '0.41';

use strict;
use vars '$ScriptDir';


package grandparent;

use strict;
sub dus { return q/grandparent-dus/ }
sub tja { return q/grandparent-tja/ }

package inheritor;

use strict;
use Exporter::Inheritor;

our $SLET;

our @ISA = qw/Exporter::Inheritor grandparent/;
our @EXPORT = qw/dus tja $SLET/;

sub _bootstrap { $SLET = q/dirk/ }
sub tja { return q/inheritor-tja/ }

package test2;

use strict;
import inheritor;

sub go { main::ok( dus() eq q/grandparent-dus/, q/implicit import works/) }

package test1;

use strict;
use vars qw/$SLET/;
import inheritor qw/tja dus $SLET/;

sub go {
	main::ok( $SLET eq q/dirk/, q/bootstrap() works/);
	main::ok( tja() eq q/inheritor-tja/, q/doesn't erase subs/);
	eval {
		no warnings;
		main::ok( !defined( *{Exporter::Inheritor::dus}{CODE} ), q/no friendly fire/);
	};
	main::ok( dus() eq q/grandparent-dus/, q/import works/);
}

package main;

use strict;
use Test::Simple tests => 5;

test1->go();
test2->go();


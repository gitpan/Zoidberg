
package my_test_class;

sub ack { 
	shift; # $self
	return 'ack', @_ ;
}

sub object { 
	my $self = shift;
	shift; #object name
	return $self->{object};
}

package my_other_test_class;

sub parent { return $_[0]->{parent} }
sub ack { 
	shift;
	return 'other_ack', @_;
}

package yet_another_test_class;

sub ack {
	shift;
	return 'yet_another_ack', @_;
}

package main;

use strict;
use Test::More tests => 22;
use Zoidberg::DispatchTable;

my $parent = bless {}, 'my_test_class';
$parent->{object} = bless {}, 'yet_another_test_class';
my $child = bless { parent => $parent }, 'my_other_test_class';


my (%tja, @tja);
tie %tja, 'Zoidberg::DispatchTable', $child;
tie @tja, 'Zoidberg::DispatchTable', $child;

$tja{trans} = sub { return 'trans', @_ };
is_deeply( [$tja{trans}->('hmm')], [qw/trans hmm/], 'table transparency to code refs');

$tja[0] =  sub { return 'trans', @_ };
is_deeply( [$tja[0]->('hmm')], [qw/trans hmm/], 'list transparency to code refs');

$tja{ping1} = q{ack};
is_deeply( [$tja{ping1}->('hmm')], [qw/other_ack hmm/], 'basic redirection for table');

push @tja, q{ack};
is_deeply( [$tja[-1]->('hmm')], [qw/other_ack hmm/], 'basic redirection for list');

$tja{ping2} = q{->object->ack};
is_deeply( [$tja{ping2}->('hmm')], [qw/yet_another_ack hmm/], 'function from other object for table');

unshift @tja, q{->object->ack};
is_deeply( [$tja[0]->('hmm')], [qw/yet_another_ack hmm/], 'function from other object for list');

$tja{ping3} = [q{->object->ack}, 'lalalalalaaaaalaaaa'];
is_deeply( [$tja{ping3}->('hmm')], [qw/yet_another_ack hmm/], 'array data type in table');
ok( tied(%tja)->[0]{ping3}[1] eq 'lalalalalaaaaalaaaa', 'data is still there in table' );

$tja[1] = [q{->object->ack}, 'lalalalalaaaaalaaaa'];
is_deeply( [$tja[1]->('hmm')], [qw/yet_another_ack hmm/], 'array data type in list');
ok( tied(@tja)->[0][1][1] eq 'lalalalalaaaaalaaaa', 'data is still there in list' );

%tja = ( 1 => [1, 'dus'], 2 => [2, 'hmm'], 3 => [3, 'dus'], 4 => 4, 5 => [5, 'tja']);
ok( tied(%tja)->tag(3) eq 'dus', 'tag works with tables' );
tied(%tja)->wipe('dus');
ok( scalar( keys %tja ) == 3, 'wipe works for table');

@tja = ( [1, 'dus'], [2, 'hmm'], [3, 'dus'], 4, [5, 'tja']);
ok( tied(@tja)->tag(2) eq 'dus', 'tag works with lists' );
tied(@tja)->wipe('dus');
ok( scalar( @tja ) == 3, 'wipe works for list');

my %dus;
tie %dus, 'Zoidberg::DispatchTable', $parent, { 
	ping1 => q{ack('1')},
	ping2 => q{->object->ack('2')},
	ping3 => q{->ack('3')},
};
is_deeply( [$dus{ping1}->('dus')], [qw/ack 1 dus/], 'basic redirection on parent from table');
is_deeply( [$dus{ping2}->('dus')], [qw/yet_another_ack 2 dus/], 'function from object on parent from table');
is_deeply( [$dus{ping3}->('dus')], [qw/ack 3 dus/], 'function from parent on parent from table');

my @dus;
tie @dus, 'Zoidberg::DispatchTable', $parent, [q{ack('1')}, q{->object->ack('2')}, q{->ack('3')}];
is_deeply( [shift(@dus)->('dus')], [qw/ack 1 dus/], 'basic redirection on parent from list');
is_deeply( [shift(@dus)->('dus')], [qw/yet_another_ack 2 dus/], 'function from object on parent from list');
is_deeply( [pop(@dus)->('dus')], [qw/ack 3 dus/], 'function from parent on parent from list');

exists $dus{hoereslet};
ok( !defined($dus{hoereslet}), 'No unwanted autovification in table' );

my $ok = 1;
@dus = (q{ack}, q{ack}, q{ack});
for (@dus) {
	my ($dus) = $_->();
	$ok = 0 unless $dus eq 'ack';
}
ok($ok == 1, 'iteration works for list');

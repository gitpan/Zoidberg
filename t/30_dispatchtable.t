
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
use Test::More tests => 10;
use Zoidberg::DispatchTable;

my $parent = bless {}, 'my_test_class';
$parent->{object} = bless {}, 'yet_another_test_class';
my $child = bless { parent => $parent }, 'my_other_test_class';


my %tja;
tie %tja, 'Zoidberg::DispatchTable', $child;

$tja{trans} = sub { return 'trans', @_ };
is_deeply( [$tja{trans}->('hmm')], [qw/trans hmm/], 'transparency to code refs');

$tja{ping1} = q{ack};
is_deeply( [$tja{ping1}->('hmm')], [qw/other_ack hmm/], 'basic redirection');

$tja{ping2} = q{->object->ack};
is_deeply( [$tja{ping2}->('hmm')], [qw/yet_another_ack hmm/], 'function from other object');


$tja{ping3} = [q{->object->ack}, 'lalalalalaaaaalaaaa'];
is_deeply( [$tja{ping3}->('hmm')], [qw/yet_another_ack hmm/], 'array data type');
ok( tied(%tja)->[0]{ping3}[1] eq 'lalalalalaaaaalaaaa', 'data is still there' );


%tja = ( 1 => [1, 'dus'], 2 => [2, 'dus'], 3 => [3, 'dus'], 4 => 4);
tied(%tja)->wipe('dus');
ok( scalar( keys %tja ) == 1, 'wipe also works');

my %dus;
tie %dus, 'Zoidberg::DispatchTable', $parent, { 
	ping1 => q{ack('1')},
	ping2 => q{->object->ack('2')},
	ping3 => q{->ack('3')},
};

is_deeply( [$dus{ping1}->('dus')], [qw/ack 1 dus/], 'basic redirection on parent');
is_deeply( [$dus{ping2}->('dus')], [qw/yet_another_ack 2 dus/], 'function from object on parent');
is_deeply( [$dus{ping3}->('dus')], [qw/ack 3 dus/], 'function from parent on parent');

ok( !defined($dus{hoereslet}), 'No unwanted autovification' ) 


package Fake::Zoid;

use Zoidberg::Utils qw/read_file/;
use Zoidberg::StringParser;

sub new {
	my $self = {};
	my $coll = read_file('./share/data/grammar.pd');
	$$self{stringparser} = Zoidberg::StringParser->new($$coll{_base_gram}, $coll);
	bless $self;
}

sub list_clothes { [qw/{settings} dus/] }

package main;

use Zoidberg::Eval;
require Test::More;

my @test_data1 = (
	['->dus', '$shell->dus', 'basic'],
	['$f00->dus', '$f00->dus', 'normal arrow'],
	['->Plug', '$shell->{objects}{Plug}', 'objects'],
	['->{Var}', '$shell->{vars}{Var}', 'vars'],
	[
		q/print 'OK' if ->{settings}{notify}/,
		q/print 'OK' if $shell->{settings}{notify}/,
		'old quoting bug'
	],
);
my @test_data2 = (
	['->Plug', '$shell->Plug', 'naked objects'],
	['->{Var}', '$shell->{Var}', 'naked vars'],
);

import Test::More tests => @test_data1 + @test_data2;

my $zoid = Fake::Zoid->new;
my $eval = Zoidberg::Eval->_new($zoid);

for (@test_data1) {
	my $dezoid = $eval->_dezoidify($$_[0]);
#	print "# $$_[0] => $dezoid\n";
	ok($dezoid eq $$_[1], $$_[2]);
}

$$zoid{settings}{naked_zoid}++;

for (@test_data2) {
	my $dezoid = $eval->_dezoidify($$_[0]);
#	print "# $$_[0] => $dezoid\n";
	ok($dezoid eq $$_[1], $$_[2]);
}

# TODO tests for "magic char"


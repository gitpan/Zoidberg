use strict;
use vars qw/$SHELL/;
use Test::More tests => 5;

my @imports =  qw/AUTOLOAD export unexport $SHELL/;

$ENV{ZOIDREF} = bless {}, 'Zoidberg::Eval'; # fake the environment
use_ok('Zoidberg::Shell', @imports);

# Checking export functions

my $dus = 'hmmm';
export( \$dus => 'dus' );
ok($dus eq $ENV{dus}, q{Export works one way});

$ENV{dus} = 'tja';
ok($dus eq $ENV{dus}, q{Export works the other way});

my @ding = qw/a b c/;
export( \@ding => 'ding');
ok($ENV{ding} =~ m/^a\Wb\Wc$/, q{Export works with arrays});

# Test OO-interface

ok(ref($SHELL) eq 'Zoidberg::Shell', q{We have a $SHELL});

# Test command, system, perl, eval

# Test autoloader


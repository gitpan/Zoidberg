use Test::Simple tests => 9;

use Zoidberg::Fish::Commands;

my $zoid = { settings => {}, aliases => {} };
my $c = Zoidberg::Fish::Commands->new($zoid, 'Commands');

print "# set command\n";
$c->set('debug');
ok $$zoid{settings}{debug}, 'set debug';
$c->set(qw/+o debug/);
ok ! $$zoid{settings}{debug}, 'set +o debug';
$c->set(qw/-o debug/);
ok $$zoid{settings}{debug}, 'set -o debug';
$c->set('debug=2');
ok $$zoid{settings}{debug} == 2, 'set debug=2';
$c->set('foo/bar');
ok $$zoid{settings}{foo}{bar}, 'set foo/bar';

print "# alias command\n";
$c->alias({dus => 'dussss'});
ok $$zoid{aliases}{dus} eq 'dussss', 'hash ref';
$c->alias('dus=hmmm');
ok $$zoid{aliases}{dus} eq 'hmmm', 'bash style';
$c->alias(dus => 'ja ja');
ok $$zoid{aliases}{dus} eq 'ja ja', 'tcsh style';
$c->alias('ftp/ls' => 'ls -l');
ok $$zoid{aliases}{ftp}{ls} eq 'ls -l', 'namespaced';
# TODO test output for list

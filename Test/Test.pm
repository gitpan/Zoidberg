package Zoidberg::Test;

our $VERSION = '0.04';

use Data::Dumper;
use base 'Zoidberg::Fish';
use Zoidberg::StringParse;
use strict;

sub init {
	my $self = shift;
	$self->{hash} = {
		'hoer' => 'billy',
		'nerd' => 'damian',
	}
}

sub parser {
	## test code for Parser
	my $self = shift;
	my $gram = shift ||  'pipe_gram';

	my @test = (
		"Dit is een gewone string",
		"Dit \\\"is een\\\" gewone string met \"quotes\" er in",
		"Dit is dus een (geneste | pipe) en dit dus niet | Dit is dus de tweede expressie.",
		"Dit zijn ( dus ( geneste { haakjes } ) enzo | hmm ) of niet | dan",
		'Dit is een \"gequote pipe | hier \" en dit | niet. Dit \| daarin tegen is een geescapede pipe',
		"En hier >> krijgen we dus < redirections.",
		"Deze string ( is ( dus ) incompleet.",
		" ff testen voor dit -> enzo -- en voor | { dit } | ja",
	);

	my $parser = Zoidberg::StringParse->new($self->parent->{grammar}, $gram);
	print "grammar: ".Dumper($parser->{grammar});

	print "\nTesting parse_string\n";
	foreach my $test (@test) {
		print "String: \"$test\"\n".Dumper($parser->parse_string($test));
		$parser->flush;
	}

	print "\nTesting parse\n";
	foreach my $test (@test) { print "String: \"$test\"\n".Dumper($parser->parse($test)); }
}

sub print {
	my $self = shift;
	$self->parent->print([qw/dit is dus een string met genoeg elementen om niet in de breedte te passen denk ik/]);
	$self->parent->print($self->{hash}, 'error');
}

sub reg {
    my $self = shift;
    $self->register_event("history_add");
}
        
sub unreg {
    my $self = shift;
    $self->unregister_event("history_add");
}

sub history_add {
    my $self = shift;
    print "hoere! event received: '$_[0]'\n";
}

sub iets {
	my $self = shift;
	$self->{parent}->print("PHP sucks ! ");
}

sub return {
	my $self = shift;
	return $self->{hash};
}

sub print_pwd {
	my $self  = shift;
	$self->parent->print('pwd:  '.$ENV{PWD});
}

sub write {
	my $self = shift;
	if ($self->{parent}->pd_write($self->{config}{file}, $self->{hash})) { $self->{parent}->print("Succeeded"); }
	else { $self->{parent}->print("Failed"); }
}

sub dump {
	my $self = shift;
	foreach my $var (@_) {
		my $string = '$self->{parent}->'.$var;
		$self->{parent}->print("Test: $var = ".Dumper(eval($string)));
	}
}

sub ask {
	my $self = shift;
	my $answer = $self->{parent}->ask("Who's your daddy ? ");
	$self->{parent}->print("You said : $answer");
}

sub main {
	my $self = shift;
	$self->{parent}->print("You called Test->main with ".join("--", @_));
}

# Preloaded methods go here.

1;
__END__

=head1 NAME

Zoidberg::Test - al kind of garbage to test zoidberg

=head1 SYNOPSIS

  there is no stable usage

=head1 DESCRIPTION

This class contains stuff developers of Zoidberg wanted to test.
Basicly its garbage -- it may change or disappear without warning.

=head2 EXPORT

None by default.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::Fish>

http://zoidberg.sourceforge.net.

=cut

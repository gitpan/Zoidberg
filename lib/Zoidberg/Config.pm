# The DATA filehandle contains default values,
# the rest is just copied on mutation

=pod

=head1 NAME

Zoidberg::Config - Install configuration for Zoidberg

=head1 SYNOPSIS

  use strict;
  use vars qw/%ZoidConf/;

  use Zoidberg::Config;
  use Data::Dumper;
  
  print Dumper \%ZoidConf;

=head1 DESCRIPTION

This package contains the installation configuration for the Zoidberg modules.
It does _not_ contain user configuration, it only enables the Zoidberg shell to find
the user configuration files. 

=head2 EXPORT

By default C<%ZoidConf> is exported.

=head1 METHODS

=over 4

=item C<file($file)>

FIXME

=item C<readfile($file)>

FIXME

=item C<output()>

Print current configuration to STDOUT.

=item C<mutate(\%config, $file)>

FIXME optional $file arg

This method overloads the current configuration with C<%config>, I<overwrites the module's source file> 
and reloads itself. I<This routine is ment to be used at install time only !> It is _not_ reversable.
The values of C<%config> should be eval-able perl statements without a C<;> or C<\n> in it.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>

=head1 SEE ALSO

L<perl>, L<Zoidberg>, L<http://zoidberg.sourceforge.net>

=cut

package Zoidberg::Config;

use strict;
use Carp;
use Exporter;
use Zoidberg::PdParse;

our $VERSION = '0.3c';

our @ISA = qw/Exporter/;
our @EXPORT = qw/%ZoidConf/;

our %ZoidConf = eval '('.join( ', ', (<DATA>) ).')';
die $@ if $@;

$Zoidberg::PdParse::base_dir = $ZoidConf{config_dir};

sub mutate {
	shift unless ref($_[0]) eq 'HASH';
	my $conf = shift;
	my $file = shift || $INC{'Zoidberg/Config.pm'};

	open IN, $INC{'Zoidberg/Config.pm'} || die 'Can\'t find my own source file !' ;
	my @source = (<IN>);
	close IN || die $!;

	open OUT, '>'.$file || die 'Can\'t overwrite source file';
	while (my $line = shift @source) { # spool normal code
		print OUT $line;
		last if $line =~ /^\s*__DATA__/;
	}
	while (my $line = shift @source) { # print data
		$line =~ /^(\'(.*?)\'\s+=>)/;
		if (exists $conf->{$2}) { 
			print OUT $1, ' ', $$conf{$2}, "\n";
			delete $$conf{$2};
		}
		else { print OUT $line }
	}
	print OUT map {"'$_'\t=> ".$$conf{$_}."\n"} keys %$conf;
	close OUT || die $!;

	# finally reload self
	do $file;
}

sub output {
	my $l = 0;
	for (keys %ZoidConf) { $l = length($_) if length($_) > $l }
	for (sort keys %ZoidConf) {
		my $p = $l - length($_);
		my $v = $ZoidConf{$_};
		$v =~ s/'/\\'/g;
		print $_, ' 'x$p, qq{ = '$v'\n};
	}
}

sub file {
	my $file = shift;
	my $path = shift || 'data_dirs';
	$file = $ZoidConf{$file} if ($file !~ /\//) && (exists $ZoidConf{$file});
	return $file if $file =~ /\//;
	for (split /:/, $ZoidConf{$path}) {
		return $_.'/'.$file if -f $_.'/'.$file
	}
	return undef;
}

sub readfile {
	my $file = shift;
	croak 'readfile needs an argument' unless $file;
	$file = file($file) unless $file =~ /\//;
	croak 'Can\'t find that file' unless defined $file;
	if ($file =~ /\.(pd)$/i) { 
		my $r = pd_read($file);
		croak "Could not read config from file: $file" unless defined $r;
		return $r;
	}
	elsif ($file =~ /\.(yaml)$/i) { croak qq/TODO yaml config file support\n/ }
	else { croak qq/Unkown file type: "$file"\n/ }
}

1;

__DATA__
'prefix'	=> '/usr/local/'
'data_dirs'	=> "$ENV{HOME}/.zoid/"
'plugin_dirs'	=> "$ENV{HOME}/.zoid/plugins/"
'settings_file'	=> 'settings.pd'
'grammar_file'	=> 'grammar.pd'
'var_dir'	=> "$ENV{HOME}/.zoid/var/"
'rcfiles'	=> "/etc/zoidrc:$ENV{HOME}/.zoidrc"

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
use Exporter;
use Zoidberg::PdParse;

our $VERSION = '0.3a';

our @ISA = qw/Exporter/;
our @EXPORT = qw/%ZoidConf/;

our @user_info = getpwuid($>);
# ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell)

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

sub readfile {
	my $file = shift;
	my $pre_eval = qq/ my \$prefix = '$ZoidConf{prefix}'; my \$conf_dir = '$ZoidConf{config_dir}'; /;
	if ($file =~ /\.(pd)$/i) { 
		my $r = pd_read($file, $pre_eval);
		die "Could not read config from file: $file\n" unless defined $r;
		return $r;
	}
	elsif ($file =~ /\.(yaml)$/i) { die qq/TODO yaml config file support\n/ }
	else { die qq/Unkown file type: "$file"\n/ }
}

1;

__DATA__
'prefix'	=> '/usr/local/'
'config_dir'	=> $user_info[7].'/.zoid/'
'plugins_dir'	=> $user_info[7].'/.zoid/plugins/'
'settings_file'	=> 'settings.pd'
'grammar_file'	=> 'grammar.pd'
'file_cache'	=> 'var/file_cache'

package Zoidberg::PluginHash;

our $VERSION = '0.52';

use strict;
use Zoidberg::Utils qw/:default read_file merge_hash list_dir/;
use Zoidberg::DispatchTable qw/wipe/;
use UNIVERSAL qw/isa/;

# $self->[0] = plugin objects hash
# $self->[1] = plugin meta data hash
# $self->[2] = parent zoid

sub TIEHASH {
	my ($class, $zoid) = @_;
	my $self = [{}, {}, $zoid];
	bless $self, $class;
	$self->hash;
	return $self;
}

sub FETCH {
	my ($self, $key) = @_;

	return $self->[0]{$key} if exists $self->[0]{$key};

	unless ($self->[1]{$key}) {
		my @caller = caller;
		error "No such object \'$key\' as requested by $caller[1] line $caller[2]";
	}

	$self->load($key) or return sub { undef };
	return $self->[0]{$key};
}

sub STORE {
	my ($self, $name, $ding) = @_;
	my $data = ref($ding) ? $ding : read_file($ding);
	$$data{config_file} = $ding unless ref($ding);

	if (exists $$data{object}) {
		$$data{object}{zoidname} = $name
			if isa $$data{object}, 'Zoidberg::Fish';
		$self->[0]{$name} = $$data{object}
	}

	# settings
	$self->[2]{settings}{$name} = merge_hash(
		$$data{config},
		$self->[2]{settings}{$name}
	) || {};
	delete $$data{config};
	
	# commands
	$$data{commands}{$_} =~ s/^(\w)/->$name->$1/
		for keys %{$$data{commands}};
	if (exists $$data{export}) {
		$$data{commands}{$_} = "->$name->$_"
			for @{$$data{export}};
		delete $$data{export};
	}
	my ($c, $s);
	while( ($c, $s) = each %{$$data{commands}} ) {
		$self->[2]{commands}{$c} = [$s, $name];
	}
	delete $$data{commands};

	# events
	$$data{events}{$_} =~ s/^(\w)/->$name->$1/
		for keys %{$$data{events}};
	if (exists $$data{import}) {
		$$data{events}{$_} = "->$name->$_"
			for @{$$data{import}};
		delete $$data{import};
	}
	while( ($c, $s) = each %{$$data{events}} ) {
		$self->[2]{events}{$c} = [$s, $name];
	}
	delete $$data{events};

	$self->[1]{$name} = $data;
	$self->load($name) if $$data{load_on_init};
}

sub FIRSTKEY { my $a = scalar keys %{$_[0][1]}; each %{$_[0][1]} }

sub NEXTKEY { each %{$_[0][1]} }

sub EXISTS { exists $_[0][1]->{$_[1]} }

sub DELETE {
	my ($self, $key) = @_;
	$self->[0]{$key}->round_up()
		if ! defined wantarray
		and ref $self->[0]{$key}
		and isa $self->[0]{$key}, 'Zoidberg::Fish';
	my $re = delete $self->[1]{$key};
	$$re{object} = delete $self->[0]{$key};
	$$re{$_} = wipe($self->[2]{$_}, $key) for qw/events commands/;
	return $re;
}

sub CLEAR { $_[0]->DELETE($_) for keys %{$_[0][1]} }

sub hash {
	my $self = shift;

	# TODO how about an ignore list for users who disagree with there admin ?

	$self->[1] = {};
	for my $dir (map "$_/plugins", @{$self->[2]{settings}{data_dirs}}) {
		next unless -d $dir;
		for (list_dir($dir)) {
			if (-d "$dir/$_") {
				/^(\w+)/ || next;
				my ($conf) = grep /^PluginConf/, list_dir("$dir/$_");
				next unless $conf and ! exists $self->[1]{$1};
				unshift @INC, "$dir/$_";
				unshift @{$self->[2]{settings}{data_dirs}}, "$dir/$_/data"
					if -d "$dir/$_/data";
				eval { $self->STORE($1, "$dir/$_/$conf") };
				complain if $@;
			}
			else {
				/^(\w+)/ || next;
				next if exists $self->[1]{$1};
				eval { $self->STORE($1, "$dir/$_") };
				complain if $@;
			}
		}
	}
}

sub load {
	my ($self, $zoidname) = @_;
	my $class = $self->[1]{$zoidname}{module};
	my @args =  $self->[1]{$zoidname}{init_args} 
		? (@{$self->[1]{$zoidname}{init_args}}) : () ;

	unless ($class) { # FIXME is this allright and does it belong in this package ?
		$self->[0]{$zoidname} = {
			parent => $self->[2],
			zoidname => $zoidname,
			settings => $self->[2]->{settings},
			config => $self->[2]->{settings}{$zoidname},
		};
		debug "Loaded stub plugin $zoidname";
		return $self->[0]{$zoidname};
	}

	debug "Going to load plugin $zoidname of class $class";
	eval "require $class" and eval {
		if ($class->isa('Zoidberg::Fish')) {
			$self->[0]{$zoidname} = $class->new($self->[2], $zoidname);
			$self->[0]{$zoidname}->init(@args);
		}
		elsif ($class->can('new')) { $self->[0]{$zoidname} = $class->new(@args) }
		else { error "Module $class doesn't seem to be Object Oriented" }
	};
	if ($@) {
		$@ =~ s/\n$/ /;
		complain "Failed to load class: $class ($@)\nDisabling plugin: $zoidname";
		$self->DELETE($zoidname);
		return undef;
	}
	else {
		debug "Loaded plugin $zoidname";
		return $self->[0]{$zoidname};
	}
}

sub round_up {
	my $self = shift;
	for (keys %{$$self[0]}) {
		$$self[0]{$_}->round_up(@_)
			if $$self[0]{$_}->isa('Zoidberg::Fish');
	}
}

1;

__END__

=head1 NAME

Zoidberg::PluginHash - magic plugin loader

=head1 SYNOPSIS

	use Zoidberg::PluginHash;
	my %plugins;
	tie %plugins, q/Zoidberg::PluginHash/, $parent;
	$plugins{foo}->bar();

=head1 DESCRIPTION

I<Documentation about Zoidberg's plugin mechanism will be provided in an other document. FIXME tell where exactly.>

This module hides some plugin loader stuff behind a transparent C<tie> 
interface. You should regard the tied hash as a simple hash with object
references. You can B<NOT> store objects in the hash, all stored values 
are expected to be either a filename or a hash with meta data.

The C<$parent> object is expected to be a hash containing at least the array
C<< $parent->{settings}{data_dirs} >> which contains the search path for 
plugin meta data. Config data for plugins is located in 
C<< $parent->{settings}{plugin_name} >>. Commands and events as defined by 
the plugins are stored in C<< $parent->{commands} >> and C<< $parent->{events} >>.
These two hashes are expected to be tied with class L<Zoidberg::DispatchTable>.

In theory you can move plugins using the ref returned after L<delete>ing them
from the hash. Practicly only the most simple plugins can be moved to an other
parent object.

B<Zoidberg::PluginHash> depends on L<Zoidberg::Utils> for reading files of various 
content types. Also it has special bindings for initialising L<Zoidberg::Fish> objects.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>,
L<Zoidberg::Fish>,
L<Zoidberg::DispatchTable>,
L<http://zoidberg.sourceforge.net>

=cut


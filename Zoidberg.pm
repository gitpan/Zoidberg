package Zoidberg;

use strict;
use vars qw/$AUTOLOAD/;
use Data::Dumper;
use Safe;
use Zoidberg::PdParse;

sub new {
	# argument: @filez
	@Zoidberg::ISA = ("Zoidberg::PdParse");
	my $class = shift;
	my $self = {};

	my $run_dir = shift;

	$self->{shell}  = {};		# system data - not to be configed (?)
	$self->{aliases} = {};		# user aliases
	$self->{cache}	= {};		# cache - not to be configed (?) - TODO non caching option
	$self->{user} = {};		    # most of the user configuration
    $self->{events} = {};       # hash used for broadcasting events
	$self->{objects} = {};		# various paralel objects

	bless($self, $class);

	$self->{run_dir} = $self->abs_path($run_dir);
	return $self;
}

sub init {
	#set defaults TODO
	#check config
	#init various objects
	my $self = shift;
	$self->{shell}{continu} = 1;

	# print welcome message
	$self->print("  ## Welcome to the Zoidberg shell Version 0.02 ##  ");

	if (@_) { $self->{config_files} = [@_]; }	# default ?
	#print "debug : got config files : ".join("--", @{$self->{config_files}})."\n";
	#print "debug: run file: ".$self->{run_dir}."\n";

	# defaults
	$self->defaults;

	# check config:
	@{$self->{config_files}} = map { $self->abs_path($_, $self->{run_dir}) } @{$self->{config_files}};
	#print "debug : got absolute config files : ".join("--", @{$self->{config_files}})."\n";
	my $config = $self->pd_read_multi(@{$self->{config_files}});
	$self->{cache}{config_backup} = $config;
	#print "debug: config: ".Dumper($config);

	#translate to absolute files
	foreach my $file (@{$config->{files}}) {
		my ($a, $b) = split(/\//, $file);
		$config->{$a}{$b} = $self->abs_path($config->{$a}{$b}, $self->{run_dir});
	}

	foreach my $cat (@{$self->{shell}{top_conf}}) {
		$self->{$cat} = $self->pd_merge($self->{$cat}, $config->{$cat});
	}
	#print "debug: ".Dumper($self);

	# init various objects:
	while (my ($n, $o) = each %{$self->{shell}{init_objects}}) {
		#print "debug : going to init: $n - config: ".Dumper($config->{$n});
        	$self->use_postponed($o);
		my $oconfig = $config->{$n} || {};
		$self->{objects}{$n} = $o->new;
		if (($o =~ /Zoidberg/)&&($o->can('init'))) { $self->{objects}{$n}->init($self, $oconfig); } # only use init for residential modules
	}

	if ($self->{objects}{Safe}) {
		$self->init_safe("Safe");
	}

	# init self
	$self->cache_path;
	if ($self->{user}{hist_pd_file} && -s $self->{user}{hist_pd_file}) {
		 $self->{cache}{hist} = $self->pd_read($self->{user}{hist_pd_file});
		 #print "debug: got history: ".Dumper($self->{cache}{hist})."from file: ".$self->{user}{hist_pd_file}."\n";
	}
	$self->{cache}{dir_hist} = [];
	$self->{cache}{dir_futr} = [];

	#print fortune
    	$self->MOTZ->fortune;
	#if ($self->{extern_bin}{fortune}) { $self->print("fortune says: \n".qx/$self->{extern_bin}{fortune}/); }
	$self->print("  ## Type help to view commands and objects");
}

sub defaults {
	my $self = shift;
	$self->{shell}{init_objects} = {
		'Buffer'	=> 'Zoidberg::Buffer',
		'Intel' 	=> 'Zoidberg::Intel',
		'Prompt'	=> 'Zoidberg::Prompt',
		'Commands'	=> 'Zoidberg::Commands',
       	'MOTZ'   	=> 'Zoidberg::MOTZ',
		'Test'		=> 'Zoidberg::Test',
        'Monitor'   => 'Zoidberg::Monitor',
		'Safe'		=> 'Safe',
        'Help'      => 'Zoidberg::Help',
	};
	$self->{shell}{top_conf} = ['aliases', 'extern_bin', 'user'];
	$self->{aliases}{bye} = "_bye";
	$self->{aliases}{cd} = "_cd";
	$self->{aliases}{chdir} = "_cd";
	$self->{aliases}{back} = "_back";
	$self->{aliases}{forw} = "_forw";
	$self->{aliases}{help} = "Help->help";
	$self->{aliases}{print} = "_print";
	$self->{aliases}{export} = "_set_env";
	$self->{cache}{max_dir_hist} = 5;
}

sub list_objects {
	my $self = shift;
	return [sort(keys(%{$self->{objects}}))];
}

sub list_aliases {
	my $self = shift;
	return [sort(keys(%{$self->{aliases}}))];
}

sub alias {
	my $self = shift;
	if ($self->{aliases}{$_[0]}) { return $self->{aliases}{$_[0]}; }
	else { return ""; }
}

sub broadcast_event {
	my $self = shift;
	my $event = shift;
	map {$_->can($event)&&$_->$event} values(%{$self->{objects}});
}

sub main_loop {
	#return: boolean -- if 1 continue if 0 die
	my $self = shift;
	$self->broadcast_event('precmd');
	$self->cache_path;
	if ($self->{objects}{Buffer}) {
		$self->parse($self->{objects}{Buffer}->read);
	}
	else {
		$self->print("No input module \'Buffer\' found.\n");
		$/ = "\n";
		print ">> ";
		my $dus = <>;
		chomp $dus;
		$self->parse($dus);
	}
	$self->broadcast_event('postcmd');
	unless ($self->{shell}{continu}) {$self->round_up; }
	return $self->{shell}{continu};
}

sub parse {
	# arguments: command string, alias bit (prohibit recurs)

	# TODO
	#	pluggable maken

	# hierarchy:
	# TODO  pipes recurs and concatonate
	# 	aliases = recurs with translation
	# 	_name = shell command	--	_\d+ = multiplicate
	# 	{} space = code
	#	^->	is sub of $self
	#	\w->\w is module
	#	/ en ./ en ~/ ~pardus/
	# 	bin in path or workdir
	# 	try to eval if eval_all bit is set

	my $self = shift;
	my $string = shift;
	my $no_recurs = shift || 0;

	$string =~ s/^\s*//;
	$string =~ m/^([^\s\n]+)(\s|\n|$)/;
	my $first = $1;

	#print "debug: got string --$string-- first is --$first--\n";

	if (!$string || ($string =~ /^[\s\n]*$/)) { return ""; } #do nothing - speed hack
	elsif (defined($self->{aliases}{$first}) && !$no_recurs) {
		#print "debug: is alias\n";
		my $new = $self->{aliases}{$first};
		$string =~ s/$first/$new/;
		return $self->parse($string, 1); 	#recurs
	}

	if ($first =~ /^_/) {
		if ($string =~ /^_[\n\s]*(\d+)/) {	# multiply by $1
			my $count = $1;
			$string =~ s/^_[\n\s]*(\d+)[\n\s]*//;
			my $return = "";
			for (1..$count) { $return = $self->parse($string) };
			return $return;
		}
		elsif ($self->{objects}{Commands}) {
			$string =~ s/^_[\n\s]*//;
			my @arg = split(/[\n\s]+/, $string);
			return $self->{objects}{Commands}->parse(@arg);
		}
	}
	elsif ($first =~ /^\\_/) { 	#escape sequence for "_"
		$string =~ s/^\\_/_/;
	}

	if ( ($first =~ /^\{/) && ($string =~ /\}[s\n]*$/) ) {
		$string =~ s/(^\{|\}[s\n]*$)//g;
		#print "debug: found code --$1--\n";
		return $self->run_eval($string);
	}
	elsif ($first =~ /^->/) {
		if ($self->{user}{call_zoidberg}) {
			$string =~ s/^->/\$self->/;
			return $self->run_sub($string);

		}
		else {
			$self->print("Calling of core functions disabled. To enable set \'{user}{call_zoidberg}\'.");
			return "";
		}
	}
	elsif ($first =~ /^([\w\d\-\_]+)(\(.*\))?->/) {
		#print "debug: is procedure call\n";
		my $module = $1;
		#print "debug: module $module\n";
		if ($self->{objects}{$module}) {
			$string =~ s/^$module/\$self->\{objects\}\{$module\}/;
			return $self->run_sub($string);
		}
		else {
			$self->print("Unknown module \'$module\'");
			return "";
		}
	}

	if (my $bin = $self->is_bin($first)) {
		#print "debug: string is $string\n";
		my @arg = split (/[\n\s]+/, $string);
		$arg[0] = $bin;
		#print "debug: array is : ".join("--", @arg)."\n";
		return system(@arg);
	}
	elsif ($self->{objects}{$first} && $self->{objects}{$first}->can('main')) {
		$string =~ s/^$first/$first->main/;
		return $self->run_sub($string);
	}

	#print "debug: is rest\n";
	if ($self->{user}{eval_all}) {
		return $self->run_eval($string);
	}
	else {
		$self->print("Unknown syntax.");
		return "";
	}
}

sub run_sub {
	my $self = shift;
	my $string = shift;
	my $tail = "";
	if ($string =~ /\(.*\)/) {
		$string =~ s/[\s\n]*([^\)]*)[\s\n]*$//;
		$tail = $1;
	}
	else {
		$string =~ s/([^\s\n]*)[\s\n]*(.*)[\s\n]*$/$1/;
		$tail = $2;
	}
	if ($tail) { $tail = "\"".$tail."\""; }
	$tail =~ s/[\s\n]+/\", \"/;
	#print "debug: tail = --$tail--\n";
	if ($string =~ /\((.*)\)$/) {
		if ($1) {
			$tail = $1.", ".$tail;
		}
		$string =~ s/\((.*)\)$//;
	}
	$string .= "(".$tail.")";
	#print "debug: going to eval: $string\n";
	my $re = eval($string);
	unless ($@) {return $re; }
	else {
		$self->print($@);
		return "";
	}
}

sub run_eval {
	my $self = shift;
	foreach my $string (@_) {
		#print "debug: trying to eval --$string--\n";
		if ($self->{objects}{Safe}) {
			my $re = $self->{objects}{Safe}->reval($string);
			print "\n";	# else the prompt could overwrite some printed data - more fancy solution ?
			return $re;
		}
		else {
			#print "debug: no Safe object\n";
			my $re = eval { eval($string) };
			unless ($@) {
				print "\n";	# idem
				return $re;
			}
			else {
				$self->print($re);
				return "";
			}
		}
	}
}

sub print {
	my $self = shift;
	my $dus = join( " ", @_);
	unless ($dus =~ /\n$/) { $dus .= "\n"; }
	print $dus;
}

sub ask {
	my $self = shift;
	if ($self->{objects}{Buffer}) {
		return $self->{objects}{Buffer}->read_question($_[0]);
	}
	else {
		unless (ref($_[0])) {
			my $string = $_[0];
			print $string;
			my $dus = <STDIN>;
			chomp $dus;
			return $dus;
		}
	}
}

sub abs_path {			# return absolute path
	# argument: string optional: reference
	my $self = shift;
	my $pattern = shift || $ENV{PWD};
	my $ref = shift || $ENV{PWD};
	$pattern =~ s/^~(\/|\s|$)/$ENV{HOME}\//;
	if ($pattern =~ /^\//) { return $pattern; }
	if ( $pattern =~ /^~([^\/\s]+)/ ) {
		if ($self->{objects}{Intel}) {
			my @info = getpwnam($1); # Returns ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell).
			$pattern =~ s/^~$1\/?/$info[7]\//;
			return $pattern;
		}
	}
	if ( $pattern =~ /^[^\.]/) {$pattern = "./".$pattern};
	if ( $pattern =~ /(^|\/)\.{1,2}(\/|\s*$)/ ) {	# match ^./ ^../ /./ /../ .. . etc
		my @guide = split(/\//, $pattern);
		my @abs = split(/\//, $ref);
		foreach my $ding (@guide) {
			unless (($ding eq ".") || ($ding eq "")) {
				if ($ding eq "..") { pop(@abs); }
				else { push @abs, $ding; }
			}
		}
		$pattern = join("/", @abs);
	}
	$pattern =~ s/\/\s*$//;		#/ comment om mn highlighting te fixen :(

	return $pattern;
}

sub cache_path {
	my $self = shift;
	if(($self->{cache}{path_string} ne $ENV{PATH}) || ($_[0] eq "force")) {
		#print "debug: going to reload path\n";
		if ($_[0] eq "force") { $self->print("Reloading path.."); }
		my @loc = reverse(split (/:/, $ENV{PATH}));
		$self->{cache}{path} = {}; #cleanup
		#print "debug: path: ".$ENV{PATH}." array: ".join("--", @loc)."\n";
		foreach my $dir (@loc) {
			if ($dir =~ /[^\/]$/) { $dir .= "/"; }
			#print "debug: scanning $dir\n";
			my %inh = $self->scan_dir($dir);
			foreach my $file (@{$inh{files}}) {
				$self->{cache}{path}{$file} = $dir.$file;
			}
		}
		$self->{cache}{path_string} = $ENV{PATH};
	}
}

sub is_bin {
	my $self = shift;
	my $first = shift;
	#print "debug: checking --$first-- in path\n";
	if ((defined $self->{cache}{path}{$first}) && (-x $self->{cache}{path}{$first})) {
		#print "debug: is bin in path\n";
		return $self->{cache}{path}{$first};
	}
	#print "debug: current dir $ENV{PWD}\n";
	my %dir = $self->scan_dir( $ENV{PWD} );
	foreach my $file (@{$dir{files}}) {
		if (($file eq $first) && (-x $file)) { return $ENV{PWD}."/".$file; }
	}
	return "";
}

sub scan_dir {
	my $self = shift;
	#print "debug: Scanning: ".$_[0]."\n";
	opendir DUS, $_[0] ;
	my @inhoud = readdir DUS ;
	closedir DUS ;
	chdir $_[0];
	shift @inhoud ; shift @inhoud ; #removing "." en ".."

	my @dirs = ();
	my @files = () ;
	foreach my $ding (sort {uc($a) cmp uc($b)} @inhoud) {

		if ((-d $ding) && !(-l $ding)) {
			push @dirs, $ding ;
		}
		elsif (-f $ding) {
			push @files, $ding;
		}
		else {
			#print "debug: unknown: $ding \n" ;
		}
	}

	chdir($ENV{PWD});
	my %result = ("dirs" => [@dirs], "files" => [@files]);
	#print "debug: dir $_[0] comtains ".Dumper(\%result);
	return %result ;
}

sub add_history {
	my $self = shift;
	my $ding = shift;
	$ding =~ s/([\'\"])/\\$1/g;		#escape quotes
	$ding =~ s/^\s*(\S.*\S)\s*$/\'$1\'/;	#strip space & put on safety quotes
	#print "debug: add hist ding is: $ding ,  max hist: ".$self->{max_hist}."\n";
	if ( $ding && !($ding eq @{$self->{cache}{hist}}[1]) ) {
		@{$self->{cache}{hist}}[0] = $ding;
		unshift @{$self->{cache}{hist}}, "";	# [0] is current prompt - should be empty
		if ($#{$self->{cache}{hist}} > $self->{user}{max_hist}) { pop @{$self->{cache}{hist}}; }
	}
	$self->{cache}{hist_p} = 0; # reset history pointer
}

sub get_hist {	# arg undef -> @hist | "back" -> $last | "forw" -> $next
	my $self = shift;
	my $act = shift || return @{$self->{cache}{hist}};
	if ($act eq "back") {	# one back in hist
		if ($self->{cache}{hist_p} < $#{$self->{cache}{hist}}) { $self->{cache}{hist_p}++; }
	}
	elsif ($act eq "forw") {	# one forward in hist
		if ($self->{cache}{hist_p}) { $self->{cache}{hist_p}--; }
	}
	my $result = $self->{cache}{hist}[$self->{cache}{hist_p}];
	$result =~ s/(^\'|\'$)//g;
	$result =~ s/\\([\'\"])/$1/g; #get rid of safety quotes
	return $result;
}

sub del_one_hist {
	my $self = shift;
	my $int = shift;
	shift @{$self->{cache}{hist}};
	shift @{$self->{cache}{hist}};
	unshift @{$self->{cache}{hist}}, "";
}

sub init_safe {
	my $self = shift;
	my $name = shift;
	if ($_[0] eq "new") { $self->{objects}{$name} = Safe->new; print "debug: new safe --$name-- ..\n"}
	$self->{objects}{$name}->reval("no strict");
	$self->{objects}{$name}->reval("use Data::Dumper");
}

sub register_event {
    my $self = shift;
    my $event = shift;
    my $object = shift;
    unless (exists $self->{events}{$event}) { $self->{events}{$event} = {} }
    my $nom = $self->{events}{$event};
    $nom->{"$object"}=$object;
}

sub registered_events {
    my $self = shift;
    my $object = shift;
    my @events;
    foreach my $event (keys %{$self->{events}}) {
        if (exists $self->{events}{$event}{"$object"}) {
            push @events, $event; 
        }
    }
    return @events;
}

sub registered_objects {
    my $self = shift;
    my $event = shift;
    return values %{$self->{events}{$event}};
}

sub unregister_event {
    my $self = shift;
    my $event = shift;
    my $object = shift;
    unless (exists $self->{events}{$event}) { return 1 }
    delete $self->{events}{$event}{"$object"};
}

sub round_up {
	my $self = shift;
	foreach my $n (keys %{$self->{objects}}) {
		#print "debug roud up: ".ref( $self->{objects}{$n})."\n";
		if ((ref( $self->{objects}{$n}) =~ /Zoidberg/)&&($self->{objects}{$n}->can('round_up'))) { $self->{objects}{$n}->round_up; }
	}

	# own roundup
	if ($self->{user}{hist_pd_file}) {
		unless ($self->pd_write($self->{user}{hist_pd_file}, $self->{cache}{hist})) {
			$self->print("Failed to write hist file: ".$self->{user}{hist_pd_file});
		}
	}
	$self->print("  # ### CU - Please fix all bugs !! ### #  ");

}

sub AUTOLOAD {
    my $self = shift;
    my $method = (split/::/,$AUTOLOAD)[-1];
    for (keys %{$self->{objects}}) {
        if (lc($_) eq lc($method)) {
            $method = $_;
            last;
        }
    }
    unless (exists $self->{objects}{$method}) {
        warn "failed to AUTOLOAD $method via package ".ref($self);
        return;
    }
    my $sub = sub {
        my $self = shift;
        return $self->{objects}{$method};
    };
    no strict 'refs';
    *{ref($self)."::".$method}=$sub;
    $self->$sub(@_);
}

sub DESTROY {
	my $self = shift;
	if ($self->{shell}{continu}) {
		$self->round_up;
	}
}

###############################
#### filthy magic-loader:) ####
###############################

sub init_postponed {
	my $self = shift;
	#print "debug postponed init got : ".join("--", @_)."\n";
	my $name = shift;
	my $class = shift;
	#print "debug : going to init: $n - config: ".Dumper($config->{$n});
	$self->use_postponed($class);
	my $oconfig = $self->{cache}{config_backup}{$name} || {};
	$self->{objects}{$name} = $class->new(@_);
	if (($class =~ /Zoidberg/)&&($class->can('init'))) { $self->{objects}{$name}->init($self, $oconfig); } # only use init for residential modules
}

sub use_postponed {
    my $self = shift;
    my $mod = shift;
    $mod =~ s{::}{/}g;
    $self->inc($mod);
    #my @trappen = split/\//,$mod;
    #for (my$i=0;$i<=$#trappen;$i++) {
    #    $self->inc(join('/',@trappen[0..$i]));
    #}
}

sub included {
    my $self = shift;
    my $mod = shift;
    unless ($INC{"$mod.pm"}) {
        return 0;
    }
    return 1;
}

sub inc {
    my $self = shift;
    my $mod = shift;
    unless ($self->included($mod)) {
        if (defined(eval "require '$mod.pm'")) {
            return 1;
        }
        else {
            $self->print("Failed to include $mod.pm: ",$@);
        }
    }
}

1;

__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Zoidberg - an other perl shell

=head1 SYNOPSIS

  use Zoidberg;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Zoidberg, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Word from the author: Coding cool features has priority over documentation, 
documentation will follow as soon as the features are stable.
(This is if the project lives long enough to see that day. )

basicly it provides a shell written in perl
(i know, yet another ...). It is intended to be a
replacement for bash in the future.

Features include:
        runs perl from shell prompt (duh!)
        config in perl code
        perl codable prompt
        perl codable key bindings
        runtime loadable modules
        regex tab expansion

planned:
        multi line editing              (soon)
        pipes                           (soon)
        jobs
        screen
        inter user communication
        wrappers for several CPAN modules like mailbox

There exist some similar projects but we want more modular functionality,
things like loading modules in runtime and using them halfway a pipe.
Also we like to the config to be hardcore perl - i.e any expression
that evaluates to a ref, so config files can contain anything from a string
to a extra module (although this would not be the preferred way to load a module).
Also one should be able to overload any basic module - like for example the prompt
generating module - while working in the shell.

=head2 EXPORT

None by default.


=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>
R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>.

=cut

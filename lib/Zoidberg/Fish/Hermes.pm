package Zoidberg::Fish::Hermes;

our $VERSION = '0.2';

use base 'Zoidberg::Fish';
use DBI;

sub init {
    my $self = shift;
    $self->{handles} = {
        map { $_, DBI->connect(@{$self->{config}{handles}{$_}}) } keys %{$self->{config}{handles}}
    };
}

sub handle {
    my $self = shift;
    if ($self->{current}) {
        return $self->{handles}{$self->{current}};
    }
    if ($self->parent->{objects}{CRM}) {
        my $crm = $self->parent->crm->db;
        if ($crm->{handles}{dealer}) {
            return $crm->{handles}{dealer};
        }
        return $crm->{handles}{main};
    }
    elsif (keys%{$self->{handles}}==1) {
        return $self->{handles}{[keys%{$self->{handles}}]->[0]};
    }
    else {
        return;
    }
}

sub parse {
    my $self = shift;
    my $qry = shift;
    my $handle = $self->handle;
    unless ($handle) { $self->parent->print("No database handle selected",'warning'); $self->parent->{exec_error}=1;return }
    my $dbh = $handle->prepare($qry);
    my $res = $dbh->execute;
    unless (defined $res) {
         $self->parent->print("The egg salad looks a little suspicious: $DBI::errstr",'error');
         $self->parent->{exec_error} = 1;
    }
    if (defined $dbh->{TYPE}){
    	$self->parent->print($dbh->fetchall_arrayref, 'sql-data','s');
    } 
}

sub ls_tables {
    my $self = shift;
    keys %{$self->ls};
}

sub ls_attributes {
    my $self = shift;
    map {@{$_}} values %{$self->{ls}};
}

sub ls_handles {
    my $self = shift;
    keys %{$self->{values}};
}
 
sub ls {
    my $self = shift;
    my $h = $self->handle;
    my $ls;
    my $tiet = $h->prepare("SHOW TABLES");
    $tiet->execute or warn "only mysql is supprted for now ... plz p4tch";
    foreach my $table (map { @{$_} } @{$tiet->fetchall_arrayref}) {
        my $tpl = $h->prepare("DESCRIBE $table");
        $tpl->execute;
        $ls->{$table} = [map {$_->[0]} @{$tpl->fetchall_arrayref}];
    }
    $ls;
}

sub help {
    my $self = shift;
    $self->parent->print("The following methods are currently implemented: ls_tables, ls_attributes, ls_handles");
}

sub intel {
    my $self = shift;


}
1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Zoidberg::Fish::Hermes - Zoidberg module SQL handling

=head1 SYNOPSIS

  use Zoidberg::Hermes;
  you really shouldnt use Hermes but use
  the included grammars to execute it
  look there for more info

=head1 ABSTRACT

 Does database stuff for zoidberg
 look in ~/.zoid/profile.pd for database settings
 
 
=head1 DESCRIPTION

 Does database stuff for zoidberg
 look in ~/.zoid/profile.pd for database settings

=head2 EXPORT

None by default.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>j.g.karssenberg@student.utwente.nlE<gt>

R.L. Zwart, E<lt>carlos@caremail.nlE<gt>

M. Dalhuijsen, E<lt>denthijs@users.sourceforge.netE<gt>

Copyright (c) 2002 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

L<Zoidberg>

L<Zoidberg::Fish>

L<http://zoidberg.sourceforge.net>

=cut

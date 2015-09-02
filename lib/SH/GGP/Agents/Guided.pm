package SH::GGP::Agents::Guided;
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;

=head1

make a new module of this code.
Implement methods from this page:
http://arrogant.stanford.edu/ggp/chapters/chapter_04.html

=cut

use vars qw(%VARIABLE);
# Enable warnings within the Parse::RecDescent module.
my $homedir;
BEGIN {
    if ($^O eq 'MSWin32') {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";
use SH::GGP::Tools::AgentBase;# qw(findroles findpropositions findactions findinits findlegalx findlegals findnext findreward findterminalp init);
# use SH::GGP::Tools::Parser qw(parse_gdl data_to_gdl);
use parent 'SH::GGP::Tools::AgentBase';

my $role;
my @roles;
my $name = 'Guided';
sub new {
    my $class_name =  shift;
    my @route = @_;
    my $self = $class_name->SUPER::new(@_);
    $self->{'game'} = [];    #contain name as key and which column number in table
    $self->{'role'} = ''; #if not used yet variables shall be true i empty.
    $self->{'roles'} =[];
    $self->{'state'} = [];       #contain current variable data for line
    $self->{'route'}= \@route;
    bless( $self, $class_name );
}


sub info {
    return [ [name=>$name], [status=>'available' ] ];
}

sub start {
my ($self,$id,$player,$world,$sc,$pc) = @_;
    #my $world = readkifraw($datarules);
    $self->{'game'} =  $world->{rules};
    $self->{'role'} =  $player;
    $self->{'roles'} = $world->{roles};
    $self->{'state'} = $world->{init};
    $self->init($world);

    return 'ready';
}

sub play {
    my ($self,$id,$move,$state) = @_;
    confess 'ERROR: $move is not defined' if !defined $move;
    if (!defined $state) {
        $state = $self->{'state'};
    }
    my @actions=$self->findlegals( $self->{'role'},$state);
    my $chose;
    if (@{$self->{'route'}}) {
        $chose = shift(@{$self->{'route'}});
    } else {
        $chose = 0;
    }
    if (@actions == 0) {
        warn $chose;
        warn $self->{'role'};
        warn Dumper $state;
        confess"No actions";
    }
    my $finalchose = $chose % @actions;
    return $actions[$finalchose];
}


sub abort {
    my ($self,$id) = @_;
    return 'done'
}

sub stop {
    my ($self,$id,$move) = @_;
    return 'done'
}

1;

=head1 AUTHOR

Slegga

=cut


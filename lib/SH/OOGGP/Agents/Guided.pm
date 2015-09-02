package SH::OOGGP::Agents::Guided;
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;


# Enable warnings within the Parse::RecDescent module.
my $homedir;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";
use SH::OOGGP::Tools::AgentBase;
use parent 'SH::OOGGP::Tools::AgentBase';

=encoding utf8

=head1 NAME

SH::OOGGP::Agents::Guided

=cut

my $role;
my @roles;
my $name = 'Guided';

=head1 SYNOPSIS

 use SH::OOGGP::Agents::Guided;
 use Data::Dumper;
 my $agent = SH::OOGGP::Agents::Guided->new('test');
 print DUmper $agent->info();

=head1 DESCRIPTION

Agent for predefined moves.

=head1 METHODS

=head2 new

Make new agent.
Parameters will be which of the legal moves i chosen. Input is the legal number.
Argument 1 is move 1, argument 2 is for move 2, etc. noop moves also counts.

=cut

sub new {
    my $class_name = shift;
    my @route      = @_;
    my $self       = $class_name->SUPER::new($name,@_);
    $self->{'game'}  = [];        #contain name as key and which column number in table
    $self->{'role'}  = '';        #if not used yet variables shall be true i empty.
    $self->{'roles'} = [];
    $self->{'state'} = [];        #contain current variable data for line
    $self->{'route'} = \@route;
    bless( $self, $class_name );
}

=head2 info

Return name and status

=cut

sub info {
    return [ [ name => $name ], [ status => 'available' ] ];
}

=head2 start

Initialize the agent

=cut

sub start {
    my ( $self, $id, $player, $world, $sc, $pc ) = @_;

    #my $world = readkifraw($datarules);
    $self->{'game'}  = $world->{rules};
    $self->{'role'}  = $player;
    $self->{'roles'} = $world->{facts}->{role};
    $self->{'state'} = $world->{init};
    $self->init($world);

    return 'ready';
}

=head2 play

Choose next move.

=cut

sub play {
    my ( $self, $id, $move, $state ) = @_;
    confess 'ERROR: $move is not defined' if !defined $move;
    if ( !defined $state ) {
        $state = $self->{'state'};
    }
    my @actions = $self->findlegals( $self->{'role'}, $state );
    my $chose;
    if ( @{ $self->{'route'} } ) {
        $chose = shift( @{ $self->{'route'} } );
    } else {
        $chose = 0;
    }
    if ( @actions == 0 ) {
        warn $chose;
        warn $self->{'role'};
        warn Dumper $state;
        confess "No actions";
    }
    my $finalchose = $chose % @actions;
    return $actions[$finalchose];
}

=head2 abort

Stop agent now.

=cut

sub abort {
    my ( $self, $id ) = @_;
    return 'done';
}

=head2 stop

Stop agent after end game.

=cut

sub stop {
    my ( $self, $id, $move ) = @_;
    return 'done';
}

1;

=head1 AUTHOR

Slegga

=cut

package SH::OOGGP::Agents::Random;
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;

=encoding utf8

=head1 NAME

SH::OOGGP::Agents::Random

=head1 SYNOPSIS

 use SH::OOGGP::Agents::Random;
 use Data::Dumper;
 my $agent = SH::OOGGP::Agents::Random->new('test');
 print DUmper $agent->info();

=head1 DESCRIPTION

Random agent.

=head1 METHODS

=cut


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
use SH::OOGGP::Tools::Parser qw(parse_gdl);
use parent 'SH::OOGGP::Tools::AgentBase';

my $role;
my @roles;
my $name = 'Random';

=head2 new

Return a new agent named Random .

=cut

sub new {
    my ($class_name) = @_;
    my $self = $class_name->SUPER::new(@_);
    $self->{'game'}  = [];    #contain name as key and which column number in table
    $self->{'role'}  = '';    #if not used yet variables shall be true i empty.
    $self->{'roles'} = [];
    $self->{'state'} = [];    #contain current variable data for line
    bless( $self, $class_name );
}

=head2 info

Return info

=cut

sub info {
    return [ [ name => $name ], [ status => 'available' ] ];
}

=head2 start

Prepare for match

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

Find next move.

=cut

sub play {
    my ( $self, $id, $move, $state ) = @_;
    confess 'ERROR: $state is not defined' if !defined $state;

    my @actions = $self->findlegals( $self->{'role'}, $state );

    #warn "actions:". join(', ',@actions);
    my $chose = int( rand(@actions) );
    return $actions[$chose];
}

=head2 abort

Clean agent after sudden end.

=cut

sub abort {
    my ( $self, $id ) = @_;
    return 'done';
}

=head2 stop

Clean up after expected end.

=cut

sub stop {
    my ( $self, $id, $move ) = @_;
    return 'done';
}

1;

=head1 AUTHOR

Slegga

=cut

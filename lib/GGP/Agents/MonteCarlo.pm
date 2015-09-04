package GGP::Agents::MonteCarlo;
use strict;
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use List::MoreUtils qw (all first_index);
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);

=encoding utf8

=head1 NAME

GGP::Agents::MonteCarlo

=head1 SYNOPSIS

 use GGP::Agents::MonteCarlo;
 use Data::Dumper;
 my $agent = GGP::Agents::MonteCarlo->new('test');
 print DUmper $agent->info();

=head1 DESCRIPTION

Work down tree to terminal or search level. Get score. write score up stream till stopped.
Return main. Main start new search.

MCTS
selection, playout, expansion, back-propagation

=head1 DESIGN

Keep track of moves and values for each state.


=head1 METHODS

=cut

my $homedir;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";
use GGP::Tools::AgentBase;
use GGP::Tools::Parser qw(parse_gdl);
use GGP::Tools::Utils qw( data_to_gdl );
use parent 'GGP::Tools::AgentBase';

my @roles;
my $name         = 'MonteCarlo';
my $defaultundef = 90;

=head2 new

Make new agent

=cut

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new(@_);
    $self->{'game'}   = [];            #contain name as key and which column number in table
    $self->{'role'}   = '';            #if not used yet variables shall be true i empty.
    $self->{'roles'}  = [];
    $self->{'state'}  = [];            #contain current variable data for line
    $self->{'status'} = 'available';

    bless( $self, $class );
}

#=head2 loginfo
#
#Log message
#
#=cut

#sub loginfo {
#    my $self    = shift;
#    my $message = shift;
#    open my $fh, '>>', $self->{'log'};
#    print $fh $message . "\n";
#    close $fh;
#}

=head2 info

Return name and status

=cut

sub info {
    my $self = shift;
    return [ [ name => $name ], [ status => $self->{'status'} ] ];
}

=head2 start

Initialize the agent

=cut

sub start {
    my ( $self, $id, $player, $world, $sc, $pc, $iter ) = @_;

    #my $world = readkifraw($datarules);
    $self->{'game'}        = $world->{rules};
    $self->{'role'}        = $player;
    $self->{'roles'}       = $world->{facts}->{role};
    $self->{'state'}       = $world->{init};
    $self->{'status'}      = 'busy';
    $self->{'oldmove'}     = 'nil';
    $self->{'turn'}        = 0;
    $self->{'searchlevel'} = 10;
    $self->loginfo('START');
    $self->init( $world, $sc, $pc, $iter );

    return 'ready';
}

=head2 play

Choose next move.

=cut

sub play {
    my ( $self, $id, $move, $state ) = @_;
    $self->{'turn'}++;
    $self->p_start_timer();
    confess 'ERROR: $state not ok' . ( $state // 'undef' ) if !ref $state eq 'HASH';
    if ( lc $move ne 'nil' ) {
        if ( !defined $self->{'oldmove'} ) {
            $self->{'oldmove'} = $move;
        }
        my $oldmove = data_to_gdl( $move->[ first_index { $_ eq $self->{'role'} } @{ $self->{'roles'} } ] );
        my $storedoldmove = data_to_gdl( $self->{'oldmove'} );
        if ( $oldmove ne $storedoldmove ) {
            $self->loginfo(
                'TURN:' . $self->{'turn'} . 'Got error on move ' . $storedoldmove . " was changed to " . $oldmove );
        }
    }
    my @actions = $self->findlegals( $self->{'role'}, $state );
    $self->loginfo( "TURN:" . $self->{'turn'} . " Actions: " . @actions );
    if ( !$#actions ) {

        #return if only one legal move
        $self->{'oldmove'} = $actions[0];
        return $actions[0];
    }

    my $move2 = $self->bestmovefirst($state);
    $self->{'oldmove'} = $move2;
    $self->loginfo( "TURN:" . $self->{'turn'} . " Move: " . data_to_gdl($move2) );
    return $move2;
}

=head2 simulate

Find next state. For looking forward. Simulate moves.

=cut

sub simulate {
    my ( $self, $move, $state ) = @_;
    confess 'ERROR: $state is not defined' if !defined $state;
    if ( $move eq 'nil' ) {
        return $state;
    }
    return $self->findnext( $move, $state );
}

=head2 bestmovefirst

Log all values for decision
return move
@action{move|count|sum}
=cut

sub bestmovefirst {
    my $self       = shift;
    my $state      = shift;
    my @actions    = $self->findlegals( $self->{'role'}, $state );
    my @sampledata = ();
    my $iam        = first_index { $_ eq $self->{'role'} } @{ $self->{'roles'} };
    my @roles      = @{ $self->{'roles'} };

    while ( !$self->p_timer_is_expired() ) {

        #
        #chose
        my ( $moveno, $move );
        for my $i ( 0 .. $#roles ) {
            my @tmpmoves = $self->findlegals( $roles[$i], $state );
            $moveno->[$i] = int( rand(@tmpmoves) );
            $move->[$i]   = $tmpmoves[ $moveno->[$i] ];
        }

        #do
        $sampledata[ $moveno->[$iam] ]{move} = $move->[$iam];    # dclone($move->[$moveno->[$iam]]);
        $sampledata[ $moveno->[$iam] ]{count}++;
        my $goal = $self->bestmoverest( 0, $self->simulate( $move, $state ) );

        #track
        $sampledata[ $moveno->[$iam] ]{sum} += $goal;
    }

    #logdata
    #$self->loginfo(data_to_gdl(\@sampledata));
    for my $smove (@sampledata) {
        next if ! defined $smove;
        $self->loginfo(
            join( " ", data_to_gdl( $smove->{move} ), ( $smove->{sum} / $smove->{count} ), $smove->{count} ) );
    }

    #warn;
    #warn Dumper @sampledata;

    #find best
    my $bestmove;
    my $highscore = -1;
    for my $data (@sampledata) {
      next if ! defined $data;
      if ( $data->{sum} / $data->{count} > $highscore ) {
        $bestmove  = $data->{move};
        $highscore = $data->{sum} / $data->{count};
      }
    }
    return $bestmove;
}

=head2 bestmoverest

For each role
keep track of moves and their values
First look for undef values, then highest value



=cut

sub bestmoverest {
    my $self  = shift;
    my $level = shift;
    my $state = shift;
    $level++;
    if ( $self->findterminalp($state) ) {
        return $self->findreward( $self->{'role'}, $state );
    }
    if ( $level > $self->{'searchlevel'} || $self->p_timer_is_expired() ) {

        #return 51;
        return $self->goal_heuristics( $state, $self->{'role'} );    # state required, role optional
    }
    $level++;
    my ( $moveno, $move );
    my @roles = @{ $self->{'roles'} };
    for my $i ( 0 .. $#roles ) {
        my @tmpmoves = $self->findlegals( $roles[$i], $state );
        $moveno->[$i] = int( rand(@tmpmoves) );
        $move->[$i]   = $tmpmoves[ $moveno->[$i] ];
    }
    my $goal = $self->bestmoverest( $level, $self->simulate( $move, $state ) );
    return $goal;
}

=head2 abort

Stop agent now.

=cut

sub abort {
    my ( $self, $id ) = @_;
    $self->{'status'} = 'available';
    $self->loginfo('END');
    return 'done';
}

=head2 stop

Stop agent after end game.

=cut

sub stop {
    my ( $self, $id, $move ) = @_;
    $self->{'status'} = 'available';
    $self->loginfo('END');
    return 'done';
}

1;

=head1 AUTHOR

Slegga

=cut

package GGP::Agents::AlphaBetaM;
use strict;
use warnings;
use autodie;
use Data::Dumper;
use Data::Compare;
use Carp;
use List::MoreUtils qw (all first_index);
use List::Util qw(min max);
use Scalar::Util qw(looks_like_number);

=encoding utf8

=head1 NAME

GGP::Agents::AlphaBetaM

=head1 SYNOPSIS

 use GGP::Agents::AlphaBetaM;
 use Data::Dumper;
 my $agent = GGP::Agents::AlphaBetaM->new('test');
 print DUmper $agent->info();

=head1 DESCRIPTION

Use classic AlphaBeta. Prefer the median legal move.
I.e choose the center row in connectFour game.

M for use of median item

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
use GGP::Tools::AgentBase;
use GGP::Tools::Parser qw(parse_gdl);
use GGP::Tools::Utils qw( data_to_gdl );
use parent 'GGP::Tools::AgentBase';

my @roles;
my $name = 'AlphaBetaM';

=head2 new

Create new object.

=cut


sub new {
    my ($class_name) = @_;
    my $self = $class_name->SUPER::new(@_);
    $self->{'game'}         = [];            #contain name as key and which column number in table
    $self->{'role'}         = '';            #if not used yet variables shall be true i empty.
    $self->{'roles'}        = [];
    $self->{'state'}        = [];            #contain current variable data for line
    $self->{'status'}       = 'available';
    $self->{'minnoofroles'} = 2;
    $self->{'maxnoofroles'} = 2;

    #     if (-f $self->{'log'}) {
    #         unlink $self->{'log'};
    #     }
    bless( $self, $class_name );
}


=head2 info

return info

=cut

sub info {
    my $self = shift;
    return [ [ name => $name ], [ status => $self->{'status'} ] ];
}

=head2 start

Prepare match.

=cut

sub start {
    my ( $self, $id, $player, $world, $sc, $pc, $iter ) = @_;
    my $mconst = 16000;

    #my $world = readkifraw($datarules);
    $self->{'game'}    = $world->{rules};
    $self->{'role'}    = $player;
    $self->{'roles'}   = $world->{facts}->{role};
    $self->{'state'}   = $world->{init};
    $self->{'status'}  = 'busy';
    $self->{'oldmove'} = 'nil';
    $self->{'turn'}    = 0;

    # warn "ABM 82\n". Dumper $world->{analyze};
    $self->{'searchlevel'} =
        ( $world->{analyze}->{firstmoves} > 1
        ? int( log($mconst) / log( $world->{analyze}->{firstmoves} ) )
        : log($mconst) );
    $self->loginfo('START');
    $self->init( $world, $sc, $pc, $iter );

    return 'ready';
}

=head2 play

Find next move.

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
            $self->loginfo( 'Got error on move ' . $storedoldmove . " was changed to " . $oldmove );
        }
    }
    my @actions = $self->findlegals( $self->{'role'}, $state );
    $self->loginfo( "TURN:" . $self->{'turn'} . " Actions: " . scalar(@actions) . " Level: " . $self->{'searchlevel'} );
    if ( !$#actions ) {

        #return if only one legal move
        $self->{'oldmove'} = $actions[0];
        return $actions[0];
    }
    my $move2 = $self->bestmove( 0, $state );
    $self->{'oldmove'} = $move2;
    $self->loginfo( "TURN:" . $self->{'turn'} . " Move: " . data_to_gdl($move2) );
    if ( $self->p_timer_is_expired() ) {
        $self->{'searchlevel'}--;
    } else {
        my $dummy = $self->p_timer_time_of_expired();
        if ( !looks_like_number($dummy) ) {
            confess $dummy;
        }
        if ( $dummy * scalar(@actions) < 1 ) {
            $self->{'searchlevel'}++;
        } else {
            my $num = $dummy * scalar(@actions);
            $self->loginfo("Ok level: $num $dummy");
        }
    }
    return $move2;
}


=head2 bestmove

return scores_ar and actions_ar
Loop trough all move warnings with a while

=cut

sub bestmove {
    my ( $self, $level, $state ) = @_;

    my @actions = $self->findlegals( $self->{'role'}, $state );
    my $action  = $actions[0];
    my $score   = 0;

    # warn "\$#actions $#actions";
    confess "$#actions less than 0" if $#actions < 0 || !defined $#actions;
    my $next_sub = $self->median_item($#actions);
    my $i        = $next_sub->();                   #use middle closure

    # If all equal then choose the one closed to the middle

    #for my $i (0 .. $#actions) {
    while ( defined $i ) {
        my $result = $self->_minscore( $self->{'role'}, $level, $actions[$i], $state, -1, 101 );
        $self->loginfo( "M: " . data_to_gdl( $actions[$i] ) . ": score $result " );
        if ( $result == 100 ) {
            return $actions[$i];
        }
        if ( $result > $score ) {
            $score  = $result;
            $action = $actions[$i];
        }
        $i = $next_sub->();
    }
    return $action;
}

sub _maxscore {
    my ( $self, $role, $level, $state, $alpha, $beta ) = @_;
    confess( "missing input got " . scalar(@_) . " ecpected 6" ) if @_ < 6;
    if ( $self->findterminalp($state) ) {
        return $self->findreward( $role, $state );
    }
    if ( $level > $self->{'searchlevel'} || $self->p_timer_is_expired() ) {
        return 51;
    }
    $level++;
    my @actions = $self->findlegals( $role, $state );
    for my $i ( 0 .. $#actions ) {
        my $result = $self->_minscore( $role, $level, $actions[$i], $state, $alpha, $beta );
        $alpha = max( $alpha, $result );
        if ( $alpha >= $beta ) {

            #            $self->loginfo($level.":".data_to_gdl($actions[$i])." score 51 $alpha,$beta");
            return $beta;
        }
    }

    #   $self->loginfo($level.":alfa:".$beta);
    return $alpha;
}

sub _minscore {
    my ( $self, $role, $level, $action, $state, $alpha, $beta ) = @_;
    confess( "missing input got " . scalar(@_) . " ecpected 6" ) if @_ < 6;
    my @opponents = $self->findopponents( $role, $state );
    if ( !@opponents ) {
        warn Dumper $state;
        confess "No support for single";
    }
    if ( $level > $self->{'searchlevel'} || $self->p_timer_is_expired() ) {

        #        $self->loginfo($level.":".data_to_gdl($action)." score 51 $alpha,$beta");
        return 51;
    }
    $level++;
    my $opponent = $opponents[0];
    my @actions = $self->findlegals( $opponent, $state );
    if ( !@actions ) {
        warn Dumper $state;
        confess "No actions for $opponent";
    }
    for my $i ( 0 .. $#actions ) {
        my $move;
        if ( $role eq $self->{'roles'}->[0] ) {
            $move = [ $action, $actions[$i] ];
        } else {
            $move = [ $actions[$i], $action ];
        }
        my $newstate = $self->findnext( $move, $state );

        #         if (Compare($state, $newstate)) {
        #             confess"States did not change.";
        #         }
        my $result = $self->_maxscore( $role, $level, $newstate, $alpha, $beta );
        $beta = min( $beta, $result );
        if ( $beta <= $alpha ) {

            #            $self->loginfo($level.":".data_to_gdl($actions[$i])." score $alpha, $alpha,$beta");
            return $alpha;
        } elsif ( $self->p_timer_is_expired() ) {

            #           $self->loginfo($level.":".data_to_gdl($action)." score 51 $alpha,$beta");
            return 51;
        }

    }

    #   $self->loginfo($level.":".data_to_gdl(@actions)." beta:".$beta);
    return $beta;
}

=head2 abort

Stop before finished

=cut

sub abort {
    my ( $self, $id ) = @_;
    $self->{'status'} = 'available';
    $self->loginfo('END');
    return 'done';
}

=head2 stop

Called after finished

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

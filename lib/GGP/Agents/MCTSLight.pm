package GGP::Agents::MCTSLight;
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

GGP::Agents::MCTSLight

=head1 SYNOPSIS

 use GGP::Agents::MCTSLight;
 use Data::Dumper;
 my $agent = GGP::Agents::MCTSLight->new('test');
 print DUmper $agent->info();

=head1 DESCRIPTION

go down tree to terminal or search level. Get score. write score up stream till stopped.
Return main. Main start new search.

=head2 DESIGN

Keep track of moves and values for each state.

=head1 METHODS

=cut

my $homedir;
use Cwd 'abs_path';

BEGIN {
    $homedir = abs_path($0);
    $homedir =~s|[^\/\\]+[\/\\][^\/\\]+$||;
}
use lib "$homedir/git/ggp-perl-base/lib";
use GGP::Tools::AgentBase;
use GGP::Tools::Parser qw(parse_gdl);
use GGP::Tools::Utils qw( data_to_gdl );
use parent 'GGP::Tools::AgentBase';

my @roles;
my $name         = 'MCTSLight';
my $defaultundef = 90;

=head2 new

Return an MCTSLight agent object.

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

# sub loginfo {
#     my $self    = shift;
#     my $message = shift;
#     open my $fh, '>>', $self->{'log'};
#     print $fh $message . "\n";
#     close $fh;
# }

=head2 info

Return info: name and status

=cut

sub info {
    my $self = shift;
    return [ [ name => $name ], [ status => $self->{'status'} ] ];
}

=head2 start

Prepare for a match with known rules.

=cut

sub start {
    my ( $self, $id, $player, $world, $sc, $pc, $iter ) = @_;

    #my $world = readkifraw($datarules);
    $self->{'game'}        = $world->{rules};
    $self->{'role'}        = $player;
    $self->{'roles'}       = dclone $world->{facts}->{role};
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
    $self->loginfo( "TURN:" . $self->{'turn'} . " Actions: " . @actions );
    if ( !$#actions ) {

        #return if only one legal move
        $self->{'oldmove'} = $actions[0];
        return $actions[0];
    }
    my ( $scores, $actidx ) = $self->bestmoveall( 0, $state );
    my $i = first_index { $_ eq $self->{'role'} } @{ $self->{'roles'} };
    my $move2 = $actidx->[$i]; # $actions[ $actidx->[$i] ];
    if ( !defined $actidx->[$i] ) {
        warn '$i:' . $i;
        warn '$actidx:' . Dumper $actidx;
        warn Dumper @actions;
        confess "\$move2 not defined";
    }
    $self->{'oldmove'} = $move2;
    $self->loginfo( "TURN:" . $self->{'turn'} . " Move: " . data_to_gdl(($move2 // ['no old move','__UNDEF__'])) );
    #return $actions[ $actidx->[$i] ];
    return $actidx->[$i];
}

sub _simulate {
    my ( $self, $move, $state ) = @_;
    confess 'ERROR: $state is not defined' if !defined $state;
    if ( $move eq 'nil' ) {
        return $state;
    }
    return $self->findnext( $move, $state );
}

=head2 bestmoveall

For each role
keep track of moves and their values
First look for undef values, then highest value



=cut

sub bestmoveall {
    my $self  = shift;
    my $level = shift;
    my $state = shift;
    confess 'ERROR: $state is not defined' if !defined $state;
    my @roles = @{ $self->{'roles'} };
    if ( $self->findterminalp($state) ) {
        my @goals = $self->findrewards($state);
        return ( \@goals, 'terminal' );
    }
    if ( $level > $self->{'searchlevel'} || $self->p_timer_is_expired() ) {
        my @goals = $self->goal_heuristics($state);    #map { 51 } @roles;
        return ( \@goals, 'timeup' );
    }
    $level++;
    my @allactions = ();                               #[role][mno]{move|value}

    #    my @lockedmoves =map { 0 } @roles;
    #    my @curractions = map { 0 } @roles;
    #    my %allscores = ();
    #    my @maxgoals = map { 0 } @roles;
    #    my @retactions = @curractions;
    for my $i ( 0 .. $#roles ) {
        my @tmpmoves = $self->findlegals( $roles[$i], $state );
        $allactions[$i] = [ map { { 'move' => $_, 'value' => undef } } @tmpmoves ];
    }

    #choose
    my $move   = [];
    my $moveno = [];
    for my $i ( 0 .. $#roles ) {
        my $next_sub = $self->median_item( $#{ $allactions[$i] } );
        my $j        = $next_sub->();                                 #use middle closure
        my ( $cmove, $cvalue );
        $cmove        = $allactions[$i][$j]{move};
        $moveno->[$i] = $j;
        $cvalue       = $allactions[$i][$j]{value} // $defaultundef;
        while ( defined $j ) {
            if ( $cvalue < ( $allactions[$i][$j]{value} // $defaultundef ) ) {
                $cmove        = $allactions[$i][$j]{move};
                $cvalue       = ( $allactions[$i][$j]{value} // $defaultundef );
                $moveno->[$i] = $j;
            }
            $j = $next_sub->();
        }
        $move->[$i] = $cmove;
    }

    #do
    my ( $scores, $dummy ) = $self->bestmoveall( $level, $self->_simulate( $move, $state ) );
    for my $i ( 0 .. $#roles ) {
        if ( !defined $allactions[$i][ $moveno->[$i] ]{value}
            || $scores->[$i] < $allactions[$i][ $moveno->[$i] ]{value} )
        {
            $allactions[$i][ $moveno->[$i] ]{value} = $scores->[$i];
        }
    }
    my @moves = ();
    for my $i ( 0 .. $#roles ) {
        for my $j ( 0 .. $#{ $allactions[$i] } ) {
            if ( !defined $moves[$i] ) {
                $moves[$i] = $allactions[$i][$j];
            } elsif ( defined $allactions[$i][$j]{value}
                && defined $moves[$i]{value}
                && $moves[$i]{value} < $allactions[$i][$j]{value} )
            {
                $moves[$i] = $allactions[$i][$j];
            }
        }
    }
    my @retscores;
    my @retactions;
    for my $move (@moves) {
        push( @retscores,  ($move->{value} // $defaultundef) );
        push( @retactions, $move->{move} );
    }

    #return best
    $self->loginfo( $level . ":" . data_to_gdl( \@retactions ) . '   ' . data_to_gdl( \@retscores ) );
    return ( \@retscores, \@retactions );
}

=head2 abort

Stop unexpectedly.

=cut

sub abort {
    my ( $self, $id ) = @_;
    $self->{'status'} = 'available';
    $self->loginfo('END');
    return 'done';
}

=head2 stop

Signal to the agent that the match has ended.

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

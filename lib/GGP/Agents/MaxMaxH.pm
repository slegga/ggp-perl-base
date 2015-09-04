package GGP::Agents::MaxMaxH;
use strict;
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use List::MoreUtils qw (all first_index);
use Scalar::Util qw(looks_like_number);
#use feature 'say';

=encoding utf8

=head1 NAME

GGP::Agents::MaxMaxH

=head1 SYNOPSIS

 use GGP::Agents::MaxMaxH;
 use Data::Dumper;
 my $agent = GGP::Agents::MaxMaxH->new();
 print Dumper $agent->info();

=head1 DESCRIPTION

Asume that all roles do chose the best legal move only looking at their own score.

H = heuristics. Means calculate goal for each state/move.

=head1 METHODS

=cut

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
use GGP::Tools::AgentBase;# qw(findroles findpropositions findactions findinits findlegalx findlegals findnext findreward findrewards findterminalp init  p_start_timer p_timer_is_expired p_timer_time_of_expired);
use GGP::Tools::Parser qw(parse_gdl);
use GGP::Tools::Utils  qw( data_to_gdl );
use parent 'GGP::Tools::AgentBase';

my @roles;
my $name = 'MaxMaxH';

=head2 new

Each role choose want give them self most goals.
H = heuristics.
Lookup goal point before end game.

=cut

sub new {
    my ( $class_name) =  $_[0];
    my $self = $class_name->SUPER::new(@_);
    $self->{'game'} = [];    #contain name as key and which column number in table
    $self->{'role'} = ''; #if not used yet variables shall be true i empty.
    $self->{'roles'} =[];
    $self->{'state'} = [];       #contain current variable data for line
    $self->{'status'} = 'available';

    if (-f $self->{'log'}) {
        unlink $self->{'log'};
    }
    bless( $self, $class_name );
    return $self;
}

=head2 loginfo

Write to log

=cut

sub loginfo {
    my $self = shift;
    my $message = shift;
    open my $fh,'>>', $self->{'log'};
    print $fh $message."\n";
    close $fh;
}

=head2 info

Report info to server.

=cut

sub info {
    my $self = shift;
    return [ [name=>$name], [status=>$self->{'status'} ] ];
}

=head2 start

Prepare for match.

=cut

sub start {
my ($self,$id,$player,$world,$sc,$pc,$iterations) = @_;
    #my $world = readkifraw($datarules);
    $self->{'game'} =    $world->{rules};
    $self->{'role'} =    $player;
    $self->{'roles'} =   $world->{facts}->{role};
    $self->{'state'} =   $world->{init};
    $self->{'status'} =  'busy';
    $self->{'oldmove'} = 'nil';
    $self->{'turn'} =    0;
    $self->{'searchlevel'}=3;
    $self->loginfo('START');
    $self->init($world,$sc,$pc,$iterations);
    $self->{'roleid'} =  first_index {$player eq $_ } @{$self->{'roles'}}; #(0,1,2 etc)

    return 'ready';
}

=head2 play

Calculate next move.

=cut

sub play {
    my ($self,$id,$move,$state) = @_;
    $self->{'turn'}++;
    $self->p_start_timer();
    confess 'ERROR: $state not ok'.($state//'undef') if !ref $state eq 'HASH';
    if (lc $move ne 'nil') {
        if (! defined $self->{'oldmove'}) {
            $self->{'oldmove'} = $move;
        }
        my $oldmove = data_to_gdl($move->[first_index {$_ eq $self->{'role'}} @{$self->{'roles'}}]);
        my $storedoldmove = data_to_gdl($self->{'oldmove'});
        if ( $oldmove ne $storedoldmove) {
            $self->loginfo('Got error on move ' .$storedoldmove." was changed to ".$oldmove);
        }
    }
    my @actions = $self->findlegals( $self->{'role'},$state);
    #warn Dumper @actions;
    $self->loginfo("TURN:".$self->{'turn'}." Actions: ".@actions);
    if (!$#actions) {
        #return if only one legal move
        $self->{'oldmove'} = $actions[0];
        return $actions[0];
    }
    my ($scores,$actidx) = $self->bestmoveall(0,$state);
    if ($actidx eq 'timeup') {
        $self->loginfo("M: ".data_to_gdl($actions[0]).": score $actidx");
        return $actions[0];
    } else {
        $self->loginfo("M: ".data_to_gdl($actidx->[$self->{'roleid'}]).": score ".$scores->[$self->{'roleid'}]);
    }
    if (ref $actidx ne 'ARRAY') {
        warn $actidx;
        warn Dumper $state;
        confess "Wrong error $actidx";
    }
    my $i = first_index {$_ eq $self->{'role'}} @{$self->{'roles'}};
    my $move2 = $actions[$actidx->[$i]];
    if (!defined $actidx->[$i]) {
        warn '$i:'.$i;
        warn '$actidx:'. Dumper $actidx;
        warn Dumper @actions;

        confess "\$move2 not defined";
    }
    $self->{'oldmove'} = $move2;
    $self->loginfo("TURN:".$self->{'turn'}." Move: ".data_to_gdl($move2));
    if( $self->p_timer_is_expired()) {
        $self->{'searchlevel'}--;
    } else {
        my $dummy = $self->p_timer_time_of_expired();
        if (! looks_like_number($dummy)) {
            confess $dummy;
        }
        if ( $dummy * @actions<1 ) {
            $self->{'searchlevel'}++;
        }
    }
    return $actions[$actidx->[$i]];
}

# Look up next simulated state

sub _simulate {
    my ($self,$move,$state) = @_;
    confess 'ERROR: $state is not defined' if !defined $state;
    if ($move eq 'nil') {
        return $state;
    }
    return $self->findnext($move,$state);
}

=head2 bestmoveall

return scores_ar and actions_ar
Loop trough all move warnings with a while

=cut

sub bestmoveall {
    my $self = shift;
    my $level = shift;
    my $state = shift;
    confess 'ERROR: $state is not defined' if !defined $state;
    my @roles = @{$self->{'roles'}};
    if ($self->findterminalp($state))    {
        my @goals = $self->findrewards($state);
        return (\@goals,'terminal');
    }
    if ($level > $self->{'searchlevel'} || $self->p_timer_is_expired()) {
        my @goals = $self->goal_heuristics($state); #map { 51 } @roles;
        # warn join(", ",@goals);
        return (\@goals,'timeup');
    }
    $level++;
    my @allactions =();
    my @lockedmoves =map { 0 } @roles;
    my @curractions = map { 0 } @roles;
    my %allscores = ();
    my $maxgoal = 0; #map { 0 } @roles;
    my @retactions = @curractions;
    for my $i (0 .. $#roles) {
        $allactions[$i] = $state->{legal}->{$state->{role}->[$i]};
        #[ findlegals( $roles[$i],$state)
        if (!ref $allactions[$i]) {
            $allactions[$i] = [ $allactions[$i] ];
        }
        if (@{$allactions[$i]} == 1) {
            $lockedmoves[$i]=1;
            $retactions[$i]=0;
        } elsif (@{$allactions[$i]} == 0) {
            warn Dumper $state;
            #warn Dumper @roles;
            warn "level: ".$level;
            confess "No legal moves for $i ".$roles[$i];
        }
    }

    while (1) {
        #test
        my $move=[];
        for my $i(0 .. $#roles) {
            $move->[$i] = $allactions[$i][$curractions[$i]];
        }
        my ($scores,$dummy) = $self->bestmoveall($level,$self->_simulate($move,$state));
        if (scalar @$scores != scalar @roles ) {
            warn Dumper $scores;
            warn Dumper @roles;
            confess "Missmatch no of scores";
        }
        $allscores{join(':',@curractions)} = $scores;
        for my $i(0 ..$#{$scores}) {
#            next if $lockedmoves[$i];
            if (!defined $scores->[$i]) {
                warn Dumper $move;
                warn Dumper $scores;
                confess "Missing score";
            }
            if ($scores->[$i] > 80) {
                $lockedmoves[$i] = 1;
                $retactions[$i] = $curractions[$i];
            }
            if ($scores->[$i] > $maxgoal) { #s[$i]) {
                $maxgoal = $scores->[$i];
                $retactions[$i] = $curractions[$i];
            }

        }

        if (all { $_ } @lockedmoves) {
            last;
        }

        #tic
        my $endflag=0;
        for my $i (0 .. $#roles) {
            if ($lockedmoves[$i]) {
                if ($i >= $#roles) {
                    $endflag=1;
                    last;
                }
                next;
            }
            if ($curractions[$i] >= $#{$allactions[$i]}) {
                if ($i >= $#roles) {
                    $endflag=1;
                    last;
                }
                $curractions[$i]=0;
                next;
            }
            $curractions[$i]++;
            last;

        }
        last if ($endflag);
    }
    my $move=[];
    for my $i(0 .. $#roles) {
        $move->[$i] = $allactions[$i][$retactions[$i]];
    }
    $self->loginfo(($level).":".data_to_gdl($move//'__UNDEF__').'   '.data_to_gdl($allscores{join(':',@retactions)}//'__UNDEF__'.join(':',@retactions)));
    return ( $allscores{join(':',@retactions)}, \@retactions );
}

=head2 abort

Handle sudden exit

=cut

sub abort {
    my ($self,$id) = @_;
    $self->{'status'} = 'available';
    $self->loginfo('END');
    return 'done'
}

=head2 stop

Handles expected stops.

=cut

sub stop {
    my ($self,$id,$move) = @_;
    $self->{'status'} = 'available';
    $self->loginfo('END');
    return 'done'
}

1;

=head1 AUTHOR

Slegga

=cut

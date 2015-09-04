package GGP::Tools::AgentBase;
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use Exporter 'import';
use List::MoreUtils qw (any none);
use Data::Compare;
use Storable qw(dclone);

my $homedir;

use Cwd 'abs_path';
BEGIN {
    $homedir = abs_path($0);
    if ($^O eq 'MSWin32') {
        $homedir =~s|\[^\]+\[^\]+$||;
    } else {
        $homedir =~s|/[^/]+/[^/]+$||;
    }
}
use lib "$homedir/lib";
use GGP::Tools::Parser qw(parse_gdl);
use GGP::Tools::StateMachine; #iqw( place_move process_move get_action_history query_item);
use GGP::Tools::Utils qw( hashify );
# our @EXPORT_OK =
#    qw(findroles findpropositions findactions findinits findlegalx findlegals findnext findreward findrewards findterminalp init findopponents p_start_timer p_timer_time_of_expired p_timer_is_expired median_item);

=encoding utf8

=head1 NAME

GGP::Tools::AgentBase

=head1 SYNOPSIS

	use GGP::Tools::AgentBase;
    use parent 'GGP::Tools::AgentBase';
    sub new_child {
        my ($class_name) = @_;
        my $self = $class_name->SUPER::new(@_);
        $self->{'game'}  = [];    #contain name as key and which column number in table
        $self->{'role'}  = '';    #if not used yet variables shall be true i empty.
        $self->{'roles'} = [];
        $self->{'state'} = [];    #contain current variable data for line
        bless( $self, $class_name );
    }

=head1 DESCRIPTION

Base class for agents. Inherit from this class when making a new agent.

=head1 METHODS

=head2 new

Takes name.
Return a new object of this class.


=cut

sub new {
    my $class_name = shift;
    my $name       = shift;
    my $self       = {};

    #    my $ggpworld;
    #    my $expire_stimer;
    #    my $expire_ptimer;
    #    my $maxiterations;
    $self->{iterations} = 0;

    #    my $stimer;
    #    my $starttime;
    #    my $ptimer;
    $self->{'log'} = "$homedir//$class_name.log";
    $self->{sm} = GGP::Tools::StateMachine->new();
    if ( -f $self->{'log'} ) {
        unlink( $self->{'log'} );
    }

    bless( $self, $class_name );
    return $self;
}

=head2 init

Initialize the agent.

=cut

sub init {
    my $self   = shift;
    my $winput = shift;
    confess "\$winput is not defined" if !defined $winput;
    $self->{expire_stimer} = shift || 30;
    $self->{expire_ptimer} = shift || 30;
    $self->{maxiterations} = shift;
    if ( !defined $self->{ggpworld} ) {
        $self->{ggpworld} = $winput;

        #     } elsif( ! Compare($ggpworld, $winput) ) {
        #         confess"ERROR: Try to change the \$world!";
    }
    $self->{goalheuristic} = $self->{ggpworld}->{analyze}->{goalheuristic};
    $self->{goalheuristicdefault} =
        100 / ( $self->{ggpworld}->{analyze}->{noofroles} > 1 ? $self->{ggpworld}->{analyze}->{noofroles} : 51 );
    return 100 / $self->{ggpworld}->{analyze}->{noofroles};

}

=head2 p_start_timer

Start timer to track when to stop processing for returning an answer in time.

=cut

sub p_start_timer {
    my $self = shift;
    my $time = time;
    $self->{starttime} = $time;
    $self->{ptimer}    = $time + $self->{expire_ptimer};
    $self->{iterations} = 0;
}

=head2 p_timer_is_expired

Return true if time has expired and time to leave.
Time left return false
Handles also maxiterations

=cut

sub p_timer_is_expired {
    my $self = shift;
    if ( $self->{maxiterations} ) {
        return 1 if ( $self->{maxiterations} <= $self->{iterations} );
        return 0;
    }
    return 0 if !$self->{ptimer};
    return time >= $self->{ptimer} ? 1 : 0;
}

=head2 p_timer_time_of_expired

Return part of total time that is gone so far.

=cut

sub p_timer_time_of_expired {
    my $self     = shift;
    my $timeused = time() - $self->{starttime};
    my $return   = $timeused / $self->{expire_ptimer};

    #warn "$return=$timeused/$expire_ptimer";
    return $return;

}

=head2 findroles

- returns an array of roles.

=cut

sub findroles {
    my $self     = shift;
    my $state_hr = shift;
    confess 'Input should not be undef' if any { !defined $_ } ($state_hr);
    return @{ $state_hr->{role} };

    # query_item($ggpworld,$state_hr,'role');
}

=head2 findpropositions(game)

- returns a sequence of propositions.

=cut

=head2 findactions(role)

- returns a sequence of actions for a specified role.

=cut

sub findactions {
    my $self     = shift;
    my $role     = shift;
    my $state_hr = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $role );
    return query_legal( $self->{ggpworld}, $state_hr, $role );
}

=head2 findinits(game)

- returns a sequence of all propositions that are true in the initial state.

=cut

sub findinits {
    my $self     = shift;
    my $state_hr = shift;
    confess 'Input should not be undef' if any { !defined $_ } ($state_hr);

    return query_item( $state_hr, 'init' );
}

=head2 findlegalx(role,state)

- returns the first action that is legal for the specified role in the specified state.

=cut

sub findlegalx {
    my $self     = shift;
    my $role     = shift;
    my $state_hr = shift;
    confess 'Input should not be undef' if any { !defined $_ } ($state_hr);
    return ( $self->{sm}->query_legal( $self->{ggpworld}, $state_hr, $role ) )[0];
}

=head2 findlegals(role,state)

- returns a sequence of all actions that are legal for the specified role in the specified state.

=cut

sub findlegals {
    my $self     = shift;
    my $role     = shift;
    my $state_hr = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $role );

    #warn Dumper $state_hr->{legal}->{$role};
    if ( ref $state_hr->{legal}->{$role} ) {
        return @{ $state_hr->{legal}->{$role} };
    } else {
        return $state_hr->{legal}->{$role};
    }
}

=head2 findnext(move,state)

- returns a sequence of all propositions that are true in the state that results from the specified roles performing the specified move in the specified state.

GDL expect all values removed and recalculated. Only constants from the rules survive ha next state.

=cut

sub findnext {
    my $self     = shift;
    my $moves    = shift;
    my $state_hr = shift;
    my $return_hr;
    confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $moves );

    #Do not do next if nil
    if ( lc $moves eq 'nil' ) {
        $return_hr = dclone($state_hr);
    } else {
        $return_hr = $self->{sm}->process_move( $self->{ggpworld}, $state_hr, $moves );
        $self->{iterations}++;
    }

    return $return_hr;
}

=head2 findreward(role,state,game)

- returns the goal value for the specified role in the specified state.

=cut

sub findreward {
    my $self     = shift;
    my $role     = shift;
    my $state_hr = shift;
    if ( !defined $state_hr ) {
        confess "Missing state_hr";
    }
    my @goals = @{ $state_hr->{goal} };

    #query_item($ggpworld,$state_hr,'goal');
    if ( !@goals ) {
        warn Dumper $state_hr;
        confess "Missing goals";
    }
    my $i = 0;
    while ( defined $goals[$i] ) {
        if ( $goals[$i][0] eq $role ) {
            return $goals[$i][1];
        }
        if ( $i >= @goals ) {
            warn Dumper @goals;
            confess "Unhandled goal report. Missing code " . $goals[$i][0] . " ne $role";
        }
        $i++;
    }

}

=head2 findrewards

Remove goals given to i.e. b

=cut

sub findrewards {
    my $self     = shift;
    my $state_hr = shift;
    if ( !defined $state_hr ) {
        confess "Missing state_hr";
    }
    my @goals = @{ $state_hr->{'goal'} };
    if ( !@goals ) {
        warn Dumper $state_hr;
        confess "No goals";
    }
    my $goal_hr = hashify(@goals);
    my @return  = ();
    for my $role ( @{ $self->{ggpworld}->{facts}->{role} } ) {
        push @return, $goal_hr->{$role};
    }
    return @return;

    #    return @{$state_hr->{'goal'}};
}

=head2 findterminalp(state,game)

- returns a boolean indicating whether the specified state is terminal.

=cut

sub findterminalp {
    my $self     = shift;
    my $state_hr = shift;
    if ( !defined $state_hr ) {
        confess "Missing state_hr";
    }
    return exists $state_hr->{'terminal'};    #query_item($ggpworld,$state_hr,'terminal');
}

=head2 findopponents

Return an array of role names that is not me.

=cut

sub findopponents {
    my $self     = shift;
    my $role     = shift;
    my $state_hr = shift;
    if ( !defined $state_hr ) {
        confess "Missing state_hr";
    }
    my @roles = $self->findroles($state_hr);
    my @return = grep { $_ ne $role } @roles;
    return @return;
}

=head2 amiincontrol

Return true if control variable is set to me.
Else false

=cut

sub amiincontrol {
    my $self     = shift;
    my $role     = shift;
    my $state_hr = shift;

    return $role eq $state_hr->{control} ? 1 : 0;
}

=head2 median_item

Take $#array
Return an unnamed sub which return next median in stream

=cut

sub median_item {
    my $self   = shift;
    my $noitem = shift;
    confess "Not a number" if !defined $noitem || $noitem < 0;
    my @items = ( 0 .. $noitem );
    return sub {
        if ( !@items ) {
            return;
        }

        #use scalar(@items) insted of $#items because of connect5
        my $i = int( scalar(@items) / 2 );
        return splice( @items, $i, 1 );
        }
}

=head2 goal_heuristics

Calculates goal value even if not the game is over.

=cut

sub goal_heuristics {
    my $self     = shift;
    my $state_hr = shift;
    my $role     = shift;
    if ( $self->{goalheuristic} ne 'yes' ) {
        if ( defined $role ) {
            return $self->{goalheuristicdefault};
        } else {
            my @return = ();
            push( @return, $self->{goalheuristicdefault} ) for @{ $self->{roles} };
            return @return;
        }
    } else {
        my @goals = $self->{sm}->query_item( $self->{ggpworld}, $state_hr, 'goal' );
        if ( defined $role ) {
            my $reward;
            for my $goal (@goals) {
                if ( $role eq $goal->[0] ) {
                    $reward = $goal->[1];
                    last;
                }
            }
            confess "Cant find role $role" if !defined $reward;
            return ( $reward + $self->{goalheuristicdefault} ) / 2;
        } else {
            my @retgoals;
            for my $goal (@goals) {
                next if none { $goal->[0] eq $_ } @{ $self->{roles} };
                my $sum = ( $goal->[1] + $self->{goalheuristicdefault} ) / 2;
                push( @retgoals, $sum );
            }
            return @retgoals;
        }
    }
}

=head2 loginfo

For logging messages. Like what am I thinking

=cut

sub loginfo {
    my $self    = shift;
    my $message = shift;
    open my $fh, '>>', $self->{'log'};
    print $fh $message . "\n";
    close $fh;
}

1;

=head1 AUTHOR

Slegga

=cut

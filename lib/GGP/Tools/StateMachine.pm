package GGP::Tools::StateMachine;

use Moo;
use autodie;
#use namespace::clean;
use Data::Dumper;
use Carp;
use Data::Compare;
use List::MoreUtils qw(any uniq first_index none);
use GGP::Tools::Utils qw( hashify extract_variables data_to_gdl logf);
use Storable qw(dclone);
use Hash::Merge qw( merge );


# our @EXPORT_OK = qw(get_init_state place_move process_move get_action_history init_state_analyze query_item);

=encoding utf8

=head1 NAME

GGP::Tools::StateMachine - Master of follow rules

=head1 SYNOPSIS

    use GGP::Tools::StateMachine;
    $state = GGP::Tools::StateMachine->new();

=head1 DESCRIPTION

API for the Agents and the match scripts/servers.

=head2 DESIGN

Keep methods

get_init_state
query_premove
query_postmove
process_move
get_result_fromrules

New object analyze
 init_state_analyze

Rest of methods put into RuleLine

=head1 METHODS

=cut

#my @kifraw =();

=head2 get_init_state

Return init state

=cut

sub get_init_state {
    my $self  = shift;
    my $world = shift;
    my $return;
    if ( defined $world->{facts} ) {
        $return = dclone( $world->{facts} );
    }
    #$return->{facts} = $world->{facts};
    @$return{ keys %{ $world->{init} } } = values %{ $world->{init} };
    my $other = $self->query_other( $world, $return, 'nil' );
    @$return{ keys %$other } = values %$other;
    my @legal = $self->query_item( $world, $return, 'legal' );
    my $legal_hr;
    if (@legal) {
        $legal_hr = hashify(@legal);
    } elsif ( exists $world->{facts}->{legal} ) {
        $legal_hr = $world->{facts}->{legal};
    } else {
        confess "Cant find legal moves";
    }
    $return->{legal} = $legal_hr;

    return $return;
}


=head2 process_part

Expand state based on rule part.
Return 1 for success and 0 for no success.
Used by Tools::Parser.

=cut

sub process_part {
    my $self = shift;

    my $rules     = shift;
    my $state_hr  = shift;
    my $moves_ar  = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $rules, $state_hr, $moves_ar );
    my @resevered = ( 'role', 'base', 'input', 'init', 'true', 'does', 'next', 'legal', 'goal', 'terminal' );
    my @tmprules  = ();
    my $return    = dclone($state_hr);

    for my $rule ( @{ $rules } ) {
        if ( ref $rule->{effect} ne 'ARRAY' ) {
            next if any { $rule->{effect} eq $_ } @resevered;
            push( @tmprules, $rule );
        } else {
            next if any { $rule->{effect}->[0] eq $_ } @resevered;
            my $trule = dclone($rule);
            push( @tmprules, $trule );
        }
    }

    # expand variables to all possibillities when introduced
    # make crossed product table generator
    # filter variables with criteria
    # return crossed list
    for my $tmprule (@tmprules) {
        my $rule = GGP::Tools::RuleLine->new(rule=>$tmprule);
        my @loop =  $rule->get_result_fromarule( $state_hr->{role}, $return, $moves_ar );

        for my $key (@loop) {
            if ( ref $key eq 'ARRAY' ) {
                my @tmp  = @$key;
                my $ikey = shift(@tmp);
                confess " ref \$key is an " . ref($ikey) . " should be a scalar" . Dumper $key if ref($ikey);
                if ( exists $return->{$ikey} && !ref $return->{$ikey} ) {
                    if ( $return->{$ikey} ne $tmp[0] ) {
                        confess "Need to handle same tag has more than one value";
                    }
                } else {
                    push( @{ $return->{$ikey} }, \@tmp );
                }
            } else {
                $return->{$key} = '[true]';
            }
        }
    }

    return $return;
}


=head2 query_other

OBSOLETE

Get all items not reserved in gdl from state
Must be calculated after next when calculate next state.
Return a array ref

=cut

sub query_other {
    my $self = shift;

    my $world    = shift;
    my $state_hr = shift;
    my $moves_ar = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $world, $state_hr, $moves_ar );
    my @resevered = ( 'role', 'base', 'input', 'init', 'true', 'does', 'next', 'legal', 'goal', 'terminal' );
    my @tmprules  = ();
    my $return    = dclone($state_hr);

    for my $rule ( @{ $world->{body} } ) {
        if ( ref $rule->{effect} ne 'ARRAY' ) {
            next if any { $rule->{effect} eq $_ } @resevered;
            push( @tmprules, $rule );
        } else {
            next if any { $rule->{effect}->[0] eq $_ } @resevered;
            my $trule = dclone($rule);
            push( @tmprules, $trule );
        }
    }

    # expand variables to all possibillities when introduced
    # make crossed product table generator
    # filter variables with criteria
    # return crossed list
    require GGP::Tools::RuleLine;
    for my $tmprule (@tmprules) {
        my $rule = GGP::Tools::RuleLine->new(rule=>$tmprule);
        my @loop = $rule->get_result_fromarule( $world->{facts}->{role}, $return, $moves_ar  );

        for my $key (@loop) {
            if ( ref $key eq 'ARRAY' ) {
                my @tmp  = @$key;
                my $ikey = shift(@tmp);
                confess " ref \$key is an " . ref($ikey) . " should be a scalar" . Dumper $key if ref($ikey);
                if ( exists $return->{$ikey} && !ref $return->{$ikey} ) {
                    if ( $return->{$ikey} ne $tmp[0] ) {
                        confess "Need to handle same tag has more than one value";
                    }
                } else {
                    push( @{ $return->{$ikey} }, \@tmp );
                }
            } else {
                $return->{$key} = '[true]';
            }
        }
    }

    return $return;
}

=head2 query_nextstate

Handles next rules, aka head rules.
Shall be removed when new code in implemented

=cut

sub query_nextstate {
    my $self = shift;

    my $world    = shift;
    my $state_hr = shift;
    my $moves    = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $world, $state_hr, $moves );
    my $item     = 'next';
    my @tmprules = ();
    my @return   = ();

    #find rules before next
    my $seen_next = 0;

    for my $rule ( @{ $world->{head} } ) {

        #        ...
        # some where here is the error
        if ( ref $rule->{effect} ne 'ARRAY' ) {
            if ( $rule->{effect} ne $item ) {
                if ($seen_next) {
                    next;
                } else {
                    push( @tmprules, $rule );
                    next;
                }
            }
            push( @tmprules, $rule );
            $seen_next = 1;
        } else {
            if ( $rule->{effect}->[0] ne $item ) {
                if ($seen_next) {
                    next;
                } else {
                    push( @tmprules, $rule );
                    next;
                }
            }
            my $trule = dclone($rule);

            #shift(@{$trule->{effect}});
            #$trule->{effect} = $trule->{effect}->[0];
            push( @tmprules, $trule );
            $seen_next = 1;
        }
    }

    # remove old value from old state
    for my $rule (@tmprules) {
        if ( ref $rule->{effect} ne 'ARRAY'){
          if ( $rule->{effect} eq $item ){
            last;
          } else {
            delete ${$state_hr}{ $rule->{effect} };
          }
        } else {
          if ( $rule->{effect}->[0] eq $item ) {
            last;
          } else {
            delete ${$state_hr}{ $rule->{effect}->[0] };
          }
        }
    }

    # prepare state old with depending rules

    while ( my $rule = shift(@tmprules) ) {
        if ( ( ref $rule->{effect} ne 'ARRAY' && $rule->{effect} eq $item ) || (ref $rule->{effect} eq 'ARRAY' && $rule->{effect}->[0] eq $item )) {
            unshift @tmprules, $rule;
            last;
        }
        my @loop = $self->get_result_fromarule( $world->{facts}->{role}, $state_hr, $moves, $rule );

        for my $key (@loop) {
            if ( ref $key eq 'ARRAY' ) {
                my @tmp  = @$key;
                my $ikey = shift(@tmp);
                confess " ref \$key is an " . ref($ikey) . " should be a scalar" . Dumper $key if ref($ikey);

                #                 if (exists $state_hr->{$ikey} && ! ref $state_hr->{$ikey}) {
                #                     if ($state_hr->{$ikey} ne $tmp[0]) {
                #                         confess "Need to handle same tag has more than one value";
                #                     }
                #                 } else {
                push( @{ $state_hr->{$ikey} }, \@tmp );

                #                 }
            } else {
                $state_hr->{$key} = '[true]';
            }
        }
    }
    @return = $self->get_result_fromrules( $world->{facts}->{role}, $state_hr, $moves, @tmprules );

    #remove next key-word
    for my $ret (@return) {
        shift @$ret;
        $ret = $ret->[0];
    }

    return @return;
}


=head2 get_result_fromrules

=cut

sub get_result_fromrules {
    my $self     = shift;
    my $roles    = shift;
    my $state_hr = shift;
    my $moves    = shift;
    my @tmprules = @_;
    confess '$self is not ok it is ' . ( ref $self || $self ) if ref $self ne 'GGP::Tools::StateMachine';

    #    warn ref $self;
    confess 'Input should not be undef' if any { !defined $_ } ( $roles, $state_hr, $moves );

    confess '$state_hr is undef' if !defined $state_hr;

    my @return = ();
    my $vars   = GGP::Tools::Variables->new();

    #return @tmpreturn;
    for my $rule (@tmprules) {

        # loop thru one and one criteria
        for my $tmpcriteria ( @{ $rule->{criteria} } ) {
            next if !$vars->get_bool();
            if ( !ref $tmpcriteria ) {
                $vars->do_and( $self->true_varstate( $state_hr, $tmpcriteria, undef, $vars ) );

                #warn $tmpcriteria."\n rule\n".Dumper $rule;
                #confess "Not a reference \$tmpcriteria";
                next;
            }

            my $criteria = dclone($tmpcriteria);
            my $func     = shift(@$criteria);
            if ( $func eq 'true' ) {
                if ( @$criteria > 1 ) {
                    confess( 'true is not implemented with more than one parameter' . Dumper $criteria);
                }
                $vars->do_and( $self->true( $state_hr, $criteria->[0], $vars ) );
            } elsif ( $func eq 'does' ) {
                $vars->do_and( $self->does( $roles, $moves, $criteria ) );
            } elsif ( $func eq 'distinct' ) {
                $vars->do_and( $vars->distinct($criteria) );
            } elsif ( $func eq 'or' ) {
                $vars->do_and($vars->do_or( $self->_or_resolve( $state_hr, $criteria, $vars ) ) );
            } elsif ( $func eq 'not' ) {
                $vars->do_and( $self->do_not( $state_hr, $criteria, $vars ) );
            } elsif (
                any {
                    $func eq $_;
                }
                ( 'base', 'input' )
                )
            {
                confess "'$func' is not implemented yet as a function";
            } else {
                $vars->do_and( $self->true_varstate( $state_hr, $func, $criteria, $vars ) );
            }
        }
        if ( $vars->get_bool() ) {
            push( @return, $self->get_effect( $rule->{effect}, $vars->get() ) );
        }

        #        print Dumper $vars->get();
        $vars->reset;
    }
    return @return;
}


=head2 init_state_analyze

modifies world dirty but works

=cut

sub init_state_analyze {
    my $self  = shift;
    my $world = shift;
    my $state = shift;

    #   warn Dumper @{$state->{legal}->{'red'}};
    my $sum   = 0;
    my @roles = @{ $world->{facts}->{role} };
    for my $role (@roles) {
        my $tmp = $state->{legal}->{$role};
        if ( ref $tmp ) {
            $sum += scalar @{$tmp};
        } else {
            $sum++;
        }
    }
    $sum -= $#roles;
    $world->{analyze}->{firstmoves} = $sum;
    my @goals = $self->query_item( $world, $state, 'goal' );
    if (@goals) {
        $world->{analyze}->{goalheuristic} = 'yes';
    } else {
        $world->{analyze}->{goalheuristic} = 'no';
    }
}

=head2 process_move

Main sub

Calculate next
Change state
terminal and goal
Get legal,


=cut

sub process_move {
    my $self     = shift;
    my $world    = shift;
    my $state_hr = shift;
    my $moves    = shift;
    my $return_hr;    #state
    my $newgoals;
    confess 'Input should not be undef' if any { !defined $_ } ( $world, $state_hr, $moves );

    #    my $storedmoves = dclone $moves;
    #    push(@actionhistory,$storedmoves);
    if ($moves ne 'nil') {
        # Normal round
        #sjekk for legal
        #    warn 'ref $moves '.ref $moves;
        for my $i ( 0 .. $#{$moves} ) {
            my $tmpmove = ref $moves->[$i] ? $moves->[$i] : [ $moves->[$i] ];
            my $tmplegal = $state_hr->{legal}->{ $state_hr->{role}->[$i] };
            my @tmplegal;
            if ( ref $tmplegal ) {
                if ( ref $tmplegal->[0] ) {
                    @tmplegal = @{$tmplegal};
                } else {
                    @tmplegal = map { [$_] } @{$tmplegal};
                }
            } else {
                @tmplegal = ( [$tmplegal] );
            }
            if ( none { $tmpmove eq $_ || Compare( $tmpmove, $_ ) } @tmplegal ) {
                logf( data_to_gdl($state_hr) );
                warn Dumper $tmpmove;
                warn Dumper @tmplegal;
                confess "Not legal move '"
                    . data_to_gdl( $moves->[$i] )
                    . "' for "
                    . $state_hr->{role}->[$i]
                    . " is not in '", data_to_gdl( \@tmplegal ) . "'";
            }
        }
    #    warn data_to_gdl($moves);
    #    warn data_to_gdl($state_hr);
    #    warn data_to_gdl($world);
        my @next = $self->query_nextstate( $world, $state_hr, $moves );
    #    warn Dumper @next;
        #remove firstlevel
        #     for my $row(@next) {
        #         $row=$row->[0];
        #     }

        my %contants = ();
        if ( exists $world->{facts} && defined $world->{facts} )
        {    #has to use camelcase for not do errors if a variable in rules is named contants
            %contants = %{ $world->{facts} };
        }
        $return_hr = dclone( \%contants );
        #$return_hr->{facts} = \%contants;
        my $new = hashify(@next);
        @$return_hr{ keys %$new } = values %$new;

    } else {
        # First initial round
        $return_hr = $state_hr;
    }
    my $other = $self->query_other( $world, $return_hr, $moves );
    @$return_hr{ keys %$other } = values %$other;

    my $is_terminal = $self->query_item( $world, $return_hr, 'terminal' );
    if ($is_terminal) {
        $return_hr->{'terminal'} = '[true]';
        my @goals = $self->query_item( $world, $return_hr, 'goal' );
        if ( !@goals ) {
            logf( data_to_gdl($return_hr) );
            confess "Didnt get goals";
        }
        $return_hr->{'goal'} = \@goals;    #end
    } else {
        my $legal_hr;
        my @legal = $self->query_item( $world, $return_hr, 'legal' );
        if (@legal) {
            $legal_hr = hashify(@legal);
        } elsif ( exists $world->{facts}->{legal} ) {
            $legal_hr = $world->{facts}->{legal};
        } else {
            confess "Cant find legal moves ";
        }
        $return_hr->{'legal'} = $legal_hr;
        if ( any { !exists $return_hr->{'legal'}->{$_} } @{ $return_hr->{role} } ) {
            logf( data_to_gdl($state_hr) );
            logf( Dumper $return_hr->{'legal'} );
            confess "Cant find legal moves2";
        }

        #         my @legals=query_item($world,$return_hr,'legal');
        #         $return_hr->{'legal'} = \@legals; #end
    }
    return $return_hr;
}

=head1 AUTHOR

Slegga

=cut

1;

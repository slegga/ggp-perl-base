package GGP::Tools::StateMachine;
use Mouse;
use Carp;
use warnings;
use strict;
use Data::Dumper;
use Data::Compare;
use autodie;
use Exporter 'import';
use List::MoreUtils qw(any uniq first_index none);
use GGP::Tools::Variables;
use GGP::Tools::Utils qw( hashify extract_variables data_to_gdl logf);
use Storable qw(dclone);
use Hash::Merge qw( merge );

# our @EXPORT_OK = qw(get_init_state place_move process_move get_action_history init_state_analyze query_item);

=encoding utf8

=head1 NAME

GGP::Tools::StateMachine - New easier to change module of SH::GGP::Tools::StateMachine

=head1 SYNOPSIS

    use GGP::Tools::StateMachine;
    $state = GGP::Tools::StateMachine->new();

=head1 DESCRIPTION

FIXME Take some of function out in own package

TODO:
Figure out how parse GDL
match ()


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

=head2 query_item

Get all items from a given reserved command state

=cut

sub query_item {
    my $self     = shift;
    my $world    = shift;
    my $state_hr = shift;
    my $item     = shift;

    confess '$item is undef' if !defined $item;
    my @tmprules = ();
    my @return   = ();

    for my $rule ( @{ $world->{body} } ) {
        if ( ref $rule->{effect} ne 'ARRAY' ) {
            next if $rule->{effect} ne $item;
            push( @tmprules, $rule );
        } else {
            next if $rule->{effect}->[0] ne $item;
            my $trule = dclone($rule);
            shift( @{ $trule->{effect} } );
            push( @tmprules, $trule );
        }
    }

    # expand variables to all possibillities when introduced
    # make crossed product table generator
    # filter variables with criteria
    # return crossed list
    @return = $self->get_result_fromrules( $world->{facts}->{role}, $state_hr, 'nil', @tmprules );
    if ( exists $world->{facts}->{$item} ) {
        my $const = dclone( $world->{facts}->{$item} );
        if ( ref $const eq 'ARRAY' ) {
            push( @return, @$const );
        } else {
            push( @return, $const );
        }
    }
    return @return;
}

=head2 process_part

Expand state based on rule part.
Return 1 for success and 0 for no success.

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
        my @loop = $self->get_result_fromarule( $state_hr->{role}, $return, $moves_ar, $tmprule );

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
    for my $tmprule (@tmprules) {
        my @loop = $self->get_result_fromarule( $world->{facts}->{role}, $return, $moves_ar, $tmprule );

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

=head2 get_result_fromarule

Do one and one rule

=cut

sub get_result_fromarule {
    my $self = shift;

    my $roles    = shift;
    my $state_hr = shift;
    my $moves    = shift;
    my $rule     = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $roles, $state_hr, $rule );
    my $vars = GGP::Tools::Variables->new();

    #return @tmpreturn;
    # loop thru one and one criteria
    for my $tmpcriteria ( @{ $rule->{criteria} } ) {
        next if !$vars->get_bool();
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
            $vars->do_and( $vars->do_or( $self->_or_resolve( $state_hr, $criteria, $vars ), $rule->{effect} ));
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
    my @return = $self->get_effect( $rule->{effect}, $vars->get() );

    #     #remove 1 array level
    #     for my $tmp(@return) {
    #         #... #debug and figure out
    #
    #  #       $tmp=$tmp->[0];
    #     }
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

=head1 do_not

Return rows that othervise whould discarded, and not rows that normally would be kept.
If no variables is included return true if false and false if true.

=cut

sub do_not {
    my $self     = shift;
    my $state_hr = shift;
    my $input    = shift;
    my $vars     = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $input, $vars );
    my $return   = { table => undef };
    my $state    = 'true';
    my $table_ar = $self->not_recresolve( $state_hr, $input, $vars );

    if ( ref $table_ar eq 'ARRAY' ) {
        if ( @$table_ar > 1 ) {
            confess "No support for complex not";
        }
        $return = $table_ar->[0];
    } else {
        $return = $table_ar;
    }
    return $return;
}

=head2 not_recresolve

Recursive resolve input. Expect a data structure where first level is an array.
Resolve one and one item to be a table.
Return an array of variable-tables

=cut

sub not_recresolve {
    my $self =shift;
    my $state_hr = shift;
    my $inputs   = shift;
    my $vars     = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $inputs, $vars );

    my $return;
    my $i = 0;
    for my $func (@$inputs) {
        confess "\$func is not defined " . Dumper $inputs if !defined $func;
        if ( ref $func eq 'ARRAY' ) {
            push( @$return, $self->not_recresolve( $state_hr, $func, $vars ) );
        } elsif ( $func eq 'distinct' ) {
            shift @$inputs;
            $return = $vars->distinct( $inputs, 'not' );
            last;
        } elsif ( $func eq 'true' ) {
            if ( ref $inputs->[1] eq 'ARRAY' ) {
                $return = $self->true( $state_hr, $inputs->[1], $vars, 'not' );
            } else {
                shift @$inputs;
                $return = $self->true( $state_hr, \@$inputs, $vars, 'not' );
            }
            last;
        } elsif (
            none {
                ref $_
            }
            @$inputs
            )
        {
            my @tinput = @$inputs;
            shift @tinput;

            # (not (line red))
            if ( none { substr( $_, 0, 1 ) eq '?' } @$inputs ) {
                $return = $self->get_varstate_as_table( $state_hr, $func, \@tinput, 'not' );
            } else {    # (not (cellOpen ?x ?y1)))
                $return = $self->true_varstate( $state_hr, $func, \@tinput, $vars, 'not' );
            }
            last;
        } else {
            confess "no support for not($func ....)";
        }
    }
    return $return;
}


#head2

#Recursive resolve input. Expect  data structures where first level is an array.
#Resolve one and one item to be a table.
#Return an array of variable-tables

#cut

sub _or_resolve {
    my $self     = shift;
    my $state_hr = shift;
    my $inputs   = shift;
    my $vars     = shift;
    if ( ref $inputs ne 'ARRAY' ) {
        logf( Dumper $inputs);
        confess "\$inputs is not an array $inputs";
    }
    my $return;
    my $i = 0;
    for my $func (@$inputs) {
        confess "\$func is not defined " . Dumper $inputs if !defined $func;
        if ( ref $func eq 'ARRAY' ) {
            push( @$return, $self->_or_resolve( $state_hr, $func, $vars ) );
        } elsif ( $func eq 'distinct' ) {
            shift @$inputs;
            $return = $vars->distinct($inputs,'or'); # return a value list. Should be row numbers in future.
            last;
        } elsif ( $func eq 'true' ) {
            $return = true( $state_hr, $inputs, $vars );
        } elsif (
            any {
                $func eq $_;
            }
            ( 'not', 'does', 'base', 'input' )
            )
        {
            confess "'$func' is not implemented yet as a function";
        } else {
            shift @$inputs;
            $return = $self->true_varstate( $state_hr, $func, $inputs, $vars );
        }
    }
    return $return;
}

=head2 get_variable_n_filter

Return variable and filter, from set?

=cut

sub get_variable_n_filter {
    my $self      = shift;
    my $values_ar = shift;
    my $i         = 0;
    my $j         = 0;
    my $return    = {};
    my $filter    = {};
    $return->{table}    = [];
    $return->{variable} = {};    # one variable for each column i n input_table
    for my $value (@$values_ar) {

        if ( substr( $value, 0, 1 ) eq '?' ) {
            if ( !exists $return->{variable}->{$value} ) {
                $return->{variable}->{$value} = $j;
                $j++;
            }
        } else {
            $filter->{$i} = $value;
        }
        $i++;
    }
    return ( $return, $filter );
}

=head2 true

Handles the true command. Will query rows from state table

=cut

sub true {
    my $self      = shift;
    my $state_hr  = shift;
    my $values_ar = shift;
    my $vars      = shift;
    my $not       = shift;
    confess '$state_hr is undef or not an hash. :' . ( $state_hr // 'undef' )
        if !defined $state_hr || ref $state_hr ne 'HASH';
    my $statekey;
    if ( ref $values_ar eq 'ARRAY' ) {
        $statekey = shift(@$values_ar);
    } else {
        $statekey  = $values_ar;
        $values_ar = undef;
    }
    return $self->true_varstate( $state_hr, $statekey, $values_ar, $vars, $not );
}

=head2 true_varstate

Called from several places.
Please comment what this function does.

=cut

sub true_varstate {
    my $self      = shift;
    my $state_hr  = shift;
    my $statekey  = shift;
    my $values_ar = shift;
    my $vars      = shift;
    my $not       = shift;
    my ( $return, $filter );
    if ( !defined $values_ar ) {

        if ($not) {
            $return->{variable} = ( exists $state_hr->{$statekey} ? 'false' : 'true' );
        } else {
            $return->{variable} = ( exists $state_hr->{$statekey} ? 'true' : 'false' );
        }
    } else {

        #confess 'Input should not be undef' if any {!defined $_} ($state_hr,$statekey,$values_ar);
        ( $return, $filter ) = $self->get_variable_n_filter($values_ar);

        if ( !exists $state_hr->{$statekey} ) {
            if ($not) {    #true outside not
                my @cvkeys =
                    sort { $return->{variable}->{$a} <=> $return->{variable}->{$b} } keys %{ $return->{variable} };
                if (@cvkeys) {
                    for my $row ( @{ $vars->{table} } ) {
                        my @line = map { $row->[ $vars->{variable}->{$_} ] } @cvkeys;
                        if (@line) {
                            push( @{ $return->{table} }, \@line );
                        }
                    }
                }
            } else {       # normal true test
                $return->{variable} = 'false';

            }
        } elsif ( ref $state_hr->{$statekey} eq 'ARRAY' ) {
            if ( !$not ) {    #true outside not
                my @stateval = @{ $state_hr->{$statekey} };
                for my $statrow (@stateval) {
                    my $i       = 0;
                    my $true    = 1;
                    my $newline = [];

                    #confess "'$statekey' '$statrow' is not an array".Dumper $values_ar if ref $statrow ne 'ARRAY';
                    if ( ref $statrow eq 'ARRAY' ) {
                        for my $val (@$statrow) {
                            if ( !defined $values_ar->[$i] ) {
                                logf( "\$val=$val \$i= $i; \$values_ar=" . Dumper $values_ar);
                                logf( "\$statrow=" . Dumper $statrow);
                                confess "Undefined.";
                            }
                            if ( exists $filter->{$i} && $filter->{$i} ne $val ) {
                                $true = 0;
                            } elsif ( substr( $values_ar->[$i], 0, 1 ) eq '?' ) {
                                push( @$newline, $val );
                            }
                            $i++;
                        }

                        if ($true) {
                            push( @{ $return->{table} }, $newline );
                        }
                    } elsif ( keys %{ $return->{variable} } == 1 ) {
                        push( @{ $return->{table} }, [$statrow] );
                    } else {
                        logf( Dumper $state_hr);
                        logf( Dumper $return);
                        logf( Dumper @stateval );
                        logf($statrow);
                        confess "'$statekey' '$statrow' is not an array" . Dumper $values_ar if ref $statrow ne 'ARRAY';
                    }
                }
            } else {    #true inside not use vars insted of state_hr
                for my $varsrow ( @{ $vars->{table} } ) {
                    my $i        = 0;
                    my $newline  = [];
                    my @testline = @$values_ar;
                    for my $i ( 0 .. $#testline ) {
                        if ( substr( $testline[$i], 0, 1 ) eq '?' ) {

                            #substitute ?x with a value
                            my $tmp = $varsrow->[ $vars->{variable}->{ $testline[$i] } ];
                            $newline->[ $return->{variable}->{ $testline[$i] } ] = $tmp;
                            $testline[$i] = $tmp;
                        }
                    }
                    unshift( @testline, $statekey );
                    if ( !$self->_true_if_row_exists( $state_hr, @testline ) ) {
                        push( @{ $return->{table} }, $newline );
                    }
                }

            }
        } elsif ( @$values_ar == 0 ) {

            if ( exists( $state_hr->{$statekey} ) && $state_hr->{$statekey} ) {
                $return->{table}    = [];
                $return->{variable} = 'true';
            }
        } else {    #only one value

            my $i       = 0;
            my $true    = 1;
            my $newline = [];
            my $val     = $state_hr->{$statekey};

            if ( exists $filter->{$i} && $filter->{$i} ne $val ) {
                $true = $not ? 1 : 0;
            } elsif ( substr( $values_ar->[$i], 0, 1 ) eq '?' ) {

                #normal
                if ( !$not ) {
                    push( @$newline, $val );
                } else {    #not true
                    for my $row ( @{ $vars->{table} } ) {
                        my $notval = $row->[ $vars->{variable}->{ $values_ar->[$i] } ];
                        $true = 0;    #obmit push $newlinw later
                        if ( $notval ne $val ) {
                            push( @{ $return->{table} }, [$notval] );
                        }
                    }
                }
            }
            $i++;
            if ($true) {
                push( @{ $return->{table} }, $newline );
            }
        }
    }
    return $return;

}

sub _true_if_row_exists {
    my $self     = shift;
    my $state_hr = shift;
    my $statekey = shift;
    my @input    = @_;
    my $return   = 0;       # 0 = not found, 1 = found
    if (@input) {
        for my $staterow ( @{ $state_hr->{$statekey} } ) {
            my $equal = 1;
            for my $j ( 0 .. $#input ) {
                if ( $input[$j] ne $staterow->[$j] ) {
                    $equal = 0;
                }
            }
            if ( $equal == 1 ) {
                $return = 1;
                last;
            }
        }
    } else {
        confess "Missing input";
    }
    return $return;
}

=head2 get_varstate_as_table

For use in recursive call.
Return on table format. That will say variable =true/false
table is always []

=cut

sub get_varstate_as_table {
    my $self     = shift;
    my $state_hr = shift;
    my $func     = shift;
    my $inputs   = shift;
    my $not      = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $func, $inputs );
    if (ref $state_hr ne 'HASH') {
        warn $state_hr;
        confess "ERROR";
    }
    my $return = { table => [], variable => ( $not ? 'true' : 'false' ) };
    if ( !exists $state_hr->{$func} ) {

        # do notthing. Return false
    } elsif ( defined $inputs && @$inputs ) {
        for my $row ( @{ $state_hr->{$func} } ) {
            if ( scalar @$row != @$inputs ) {
                logf( data_to_gdl($row) );
                logf( data_to_gdl($inputs) );
                confess "Not equal no of data";
            }
            my $like = 1;
            for my $i ( 0 .. $#{$inputs} ) {
                if ( $row->[$i] ne $inputs->[$i] ) {
                    $like = 0;
                }
                $i++;
            }
            if ($like) {
                $return->{variable} = $not ? 'false' : 'true';    #Return matchining line
            }
        }
    } else {
        if ( any { $_ eq $func } keys %$state_hr ) {
            $return->{variable} = $not ? 'false' : 'true';
        }
    }
    return $return;
}

# recursive parse arrays

sub _rec_get_effect {
    my $self      = shift;
    my $array_ref = shift;
    my $line      = shift;
    my $variables = shift;
    my $return_ar = [];
    for my $value (@$array_ref) {
        if ( ref $value eq 'ARRAY' ) {
            push( @$return_ar, $self->_rec_get_effect( $value, $line, $variables ) );
        } elsif (
            any {
                $_ eq $value;
            }
            ( keys %{ $variables->{variable} } )
            )
        {    #a known variable
                # newline bla bla
            push( @$return_ar, $line->[ $variables->{variable}->{$value} ] );
        } else {    # static
            push( @$return_ar, $value );
        }
    }
    return $return_ar;
}

=head2 get_effect

Calculate effect
Return an array of effects

=cut

sub get_effect {
    my $self      = shift;
    my $effect    = shift;
    my $variables = shift;
    my @return    = ();
    my @evari     = ();
    return () if $variables->{true} == 0;
    if ( ref $effect eq 'ARRAY' ) {
        @evari = extract_variables($effect);
        if ( !@evari ) {
            push( @return, $effect );
        } else {
            for my $line ( @{ $variables->{table} } ) {
                my $newline = $self->_rec_get_effect( $effect, $line, $variables );
                push( @return, $newline );
            }
        }
        if ( @return > 65 ) {
            my %uniq;
            if ( !ref $return[0] ) {
                logf( Dumper $return[0] );
                confess "Not an array";
            }

            # if array of arrays return all
            if ( any { ref $_ } @{ $return[0] } ) {
                return @return;
            }
            for my $line (@return) {

                # print join(';',$line->[0]->[0]);
                $uniq{ join( ';', @{$line} ) } = 1;
            }
            my @return2 = map { [ split( ';', $_ ) ] } keys %uniq;

            # must remove one array ref level
            # make ha hash
            # set $uniq{join(';',inner array) =1;
            # make array of key
            # put on one level of array ref
            #            warn "new:".scalar @return2;
            @return = @return2;
        }
        return @return;
    } else {
        return $effect;
    }
}

=head2 does

Look for specific moves.
Operate different than true.
states are on format
cell:
    -
        - 1
        - 1
        - b
while moves are on:
-
    - mark
    - 1
    - 1

$input_ar holds the "criteria"

=cut

sub does {
    my $self     = shift;
    my $roles    = shift;
    my $moves_ar = shift;    #[[mark,1,1],noop]
    my $input_ar = shift;
    confess 'Input should not be undef' if any { !defined $_ } ( $roles, $moves_ar, $input_ar );
    my $role      = shift(@$input_ar);
    my $values_ar = shift(@$input_ar);
    return { variable => 'false' } if $moves_ar eq 'nil';
    my @moves = @$moves_ar;

    if (@$input_ar) {
        confess("Expect only 2 paramters for does");
    }
    my $critkey;
    if ( ref $values_ar ) {
        $critkey = shift(@$values_ar);
    } else {
        $critkey = $values_ar;
        undef($values_ar);
    }
    my ( $return, $filter ) = $self->get_variable_n_filter($values_ar);
    my @tmproles;
    if ( substr( $role, 0, 1 ) eq '?' ) {
        while ( my ( $key, $value ) = each %{ $return->{variable} } ) {
            $return->{variable}->{$key} = $value + 1;
        }
        $return->{variable}->{$role} = 0;
        @tmproles = @$roles;
    } else {
        @tmproles = ($role);
    }
    for my $tmprole (@tmproles) {
        my $h = first_index { $_ eq $tmprole } @$roles;
        if ( ref $moves[$h] eq 'ARRAY' ) {
            my @stateval = @{ $moves[$h] };
            my $i        = 0;
            my $movkey   = shift(@stateval);
            next if ( $critkey ne $movkey );
            my $true    = 1;
            my $newline = [];
            for my $statrow (@stateval) {

                if ( exists $filter->{$i} && $filter->{$i} ne $statrow ) {
                    $true = 0;
                } elsif ( !defined $values_ar ) {
                    logf( $statrow . "\n" . Dumper @moves );
                } elsif ( substr( $values_ar->[$i], 0, 1 ) eq '?' ) {
                    push( @$newline, $statrow );
                }
                $i++;
            }
            if ($true) {
                if ( exists $return->{variable}->{$role} ) {
                    unshift( @$newline, $roles->[$h] );
                }
                push( @{ $return->{table} }, $newline );
            }
        } elsif ( !defined $moves[$h] ) {
            logf( Dumper @moves );
            logf( Dumper $input_ar);
            confess "Move is undefined";

        } else {    #only one value
            my $true    = 1;
            my $newline = [];
            if ( !exists $moves[$h] ) {
                next;
            }
            my $val = $moves[$h];

            if ( exists $filter->{0} && $filter->{0} ne $val ) {
                $true = 0;
            } elsif ( $val ne $critkey ) {
                $true = 0;
            } elsif ( !defined $values_ar ) {
                $true = 1;
            } elsif ( substr( $values_ar->[0], 0, 1 ) eq '?' ) {
                push( @$newline, $val );
            }
            if ($true) {
                if ( exists $return->{variable}->{$role} ) {
                    unshift( @$newline, $roles->[$h] );
                }
                push( @{ $return->{table} }, $newline );
            }
        }
    }
    return $return;

}

# =head2 do_not
#
# Return rows that otherwise would discarded, and not rows that normally would be kept.
# If no variables is included return true if false and false if true.
#
# =cut
#
# sub do_not {
#     my $self     = shift;
#     my $state_hr = shift;
#     my $input    = shift;
#     my $vars     = shift;
#     confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $input, $vars );
#     my $return   = { table => undef };
#     my $state    = 'true';
#     my $table_ar = $self->not_recresolve( $state_hr, $input, $vars );
#
#     if ( ref $table_ar eq 'ARRAY' ) {
#         if ( @$table_ar > 1 ) {
#             confess "No support for complex not";
#         }
#         $return = $table_ar->[0];
#     } else {
#         $return = $table_ar;
#     }
#     return $return;
# }

=head2 not_recresolve

Recursive resolve input. Expect a data structure where first level is an array.
Resolve one and one item to be a table.
Return an array of variable-tables

=cut

# sub not_recresolve {
#     my $self     = shift;
#     my $state_hr = shift;
#     my $inputs   = shift;
#     my $vars     = shift;
#     confess 'Input should not be undef' if any { !defined $_ } ( $state_hr, $inputs, $vars );
#
#     my $return;
#     my $i = 0;
#     for my $func (@$inputs) {
#         confess "\$func is not defined " . Dumper $inputs if !defined $func;
#         if ( ref $func eq 'ARRAY' ) {
#             push( @$return, $self->not_recresolve( $state_hr, $func, $vars ) );
#         } elsif ( $func eq 'distinct' ) {
#             shift @$inputs;
#             $return = $vars->distinct( $inputs, 'not' );
#             last;
#         } elsif ( $func eq 'true' ) {
#             if ( ref $inputs->[1] eq 'ARRAY' ) {
#                 $return = $self->true( $state_hr, $inputs->[1], $vars, 'not' );
#             } else {
#                 shift @$inputs;
#                 $return = $self->true( $state_hr, \@$inputs, $vars, 'not' );
#             }
#             last;
#         } elsif (
#             none {
#                 ref $_;
#             }
#             @$inputs
#             )
#         {
#             my @tinput = @$inputs;
#             shift @tinput;
#
#             # (not (line red))
#             if ( none { substr( $_, 0, 1 ) eq '?' } @$inputs ) {
#                 $return = $self->get_varstate_as_table( $state_hr, $func, \@tinput, 'not' );
#             } else {    # (not (cellOpen ?x ?y1)))
#                 $return = $self->true_varstate( $state_hr, $func, \@tinput, $vars, 'not' );
#             }
#             last;
#         } else {
#             confess "no support for not($func ....)";
#         }
#     }
#     return $return;
# }
#
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

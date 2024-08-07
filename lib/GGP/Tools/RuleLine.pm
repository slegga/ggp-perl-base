package GGP::Tools::RuleLine;

use Data::Dumper;
use Data::Compare;
use Carp;
use List::MoreUtils qw(any uniq first_index none sort_by);
use GGP::Tools::Variables;
use GGP::Tools::Utils qw( extract_variables data_to_gdl logf);
use Storable qw(dclone);
use Hash::Merge qw( merge );
use Mojo::Base -base,-strict,-signatures;

=encoding utf8

=head1 NAME

GGP::Tools::RuleLine - Handle one rule

=head1 SYNOPSIS

    use GGP::Tools::RuleLine;
    $state = GGP::Tools::RuleLine->new(rule=>{effect=>'effect',criteria=>{active=>'player2'}});

=head1 DESCRIPTION

Handle a rule line. Uses facts to calculate effects.

=head1 ATTRIBUTES

=cut

has 'rule';

has 'facts';

=head1 METHODS

=head2 get_facts

    my $facts = $self->get_facts({player=>'white'},{...} );

Calculates pre calculated facts for a rule.

Return array if not

=cut

sub get_facts($self, $worldfacts, $varlookups) {   # give lookupsvariables if any
    my $vars = GGP::Tools::Variables->new();
    for  my $fact(@{$self->facts}) {
        next if !$vars->get_bool();
        my $func     = shift(@$fact);
        $vars->do_and( $self->true_varstate($worldfacts , $func, $fact, $vars ) );
    }
    if (! $varlookups) {
      return $vars->get();
    } else {
      my $return;

      #make a hash like {'val1;val2'=>[['val1','val2','val3'],['val1','val2','val4']]}
      my $facts = $vars->get();
      my ($table,$filter) = get_variable_n_filter($varlookups->[0]);
      # GET VARCOMMON ID-PLACE
      # my ($commonvars,$tmp) = $vars->compare_variablenames(keys%{$table->{variable}},$worldfacts->{variable});
      # find lookup colid
      my %varidxs = ();
      my $world = (keys %{$facts->{variable}});
      $world--;
      for my $c(@{$varlookups->[0]}) {
        for my $i(keys %{$facts->{variable}}) {
#          warn "$c $i";
          if ($c eq $i) {
             $varidxs{$facts->{variable}->{$i}}=$i ; #turnaround
          }
        }
      }
      $return->{':colindex'}=\%varidxs;
      $return->{variable} = $facts->{variable};
      for my $row(@{$facts->{table}}) {
        my $key = join(';',@{$row}[keys %varidxs]);
        if (length $key == 2) {
          warn $key.'-'.join(',',keys %varidxs);
          warn  Dumper $row;
          die "gdfdfg";
        }
        push @{$return->{$key}},$row;
      }
#      warn Dumper $return;
#      die;
      return $return;
    }
}

=head2 get_result_fromarule

Do one and one rule

=cut


sub get_result_fromarule($self, $roles, $state_hr, $moves) {
    confess 'Input should not be undef' if any { !defined $_ } ( $roles, $state_hr, $moves );
    my $vars = GGP::Tools::Variables->new();

    #return @tmpreturn;
    # loop thru one and one criteria
    for my $tmpcriteria ( @{ $self->rule->{criteria} } ) {
        next if !$vars->get_bool();
        my $criteria = ref $tmpcriteria ? dclone($tmpcriteria): [$tmpcriteria];
        my $func     = shift(@$criteria);
        if ( $func eq 'true' ) {
            if ( @$criteria > 1 ) {
                confess( 'true is not implemented with more than one parameter' . Dumper $criteria);
            }
            $vars->do_and( $self->true( $state_hr, $criteria->[0], $vars, 0 ) );
        } elsif ( $func eq ':facts') {
            # Breakes a pathern thar $vars modifies $vars.
            $vars = $self->_true_facts($state_hr, $self->rule, $criteria->[0], $vars);
        } elsif ( $func eq 'does' ) {
            $vars->do_and( $self->does( $roles, $moves, $criteria ) );
        } elsif ( $func eq 'distinct' ) {
            $vars->do_and( $vars->distinct($criteria) );
        } elsif ( $func eq 'or' ) {
            $vars->do_and( $vars->do_or( $self->_or_resolve( $state_hr, $criteria, $vars ), $self->rule->{effect} ));
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
    my @return = $self->get_effect( $self->rule->{effect}, $vars->get() );

    return @return;

}


=head2 do_not

    $ruleline->do_not({active=>'playera'},...,...);

Return rows that othervise whould discarded, and not rows that normally would be kept.
If no variables is included return true if false and false if true.

=cut

sub do_not($self,$state_hr,$input,$vars) {
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

sub not_recresolve( $self, $state_hr, $inputs, $vars) {
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
            $return = $vars->distinct($inputs); # return a value list. Should be row numbers in future.
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

sub true( $self,$state_hr, $values_ar, $vars, $not ) {
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
                    my $variabletmp =  $vars->variable;
                    for my $row ( @{ $vars->table } ) {
                        my @line = map { $row->[ $variabletmp->{$_} ] } @cvkeys;
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
                my $variabletmp = $vars->variable;
                for my $varsrow ( @{ $vars->table } ) {
                    my $i        = 0;
                    my $newline  = [];
                    my @testline = @$values_ar;
                    for my $i ( 0 .. $#testline ) {
                        if ( substr( $testline[$i], 0, 1 ) eq '?' ) {

                            #substitute ?x with a value
                            my $tmp = $varsrow->[ $variabletmp->{ $testline[$i] } ];
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
                    my $variabletmp = $vars->variable;
                    for my $row ( @{ $vars->table } ) {
                        my $notval = $row->[ $variabletmp->{ $values_ar->[$i] } ];
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

# called from true_varstate
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

# =head2 true_facts
# $vars = $self->_true_facts($state_hr, $self->rule, $criteria->[0], $vars)
# Retrun variables;
sub _true_facts( $self, $state_hr,  $rule,  $values_ar, $vars) {
    confess '$state_hr is undef or not an hash. :' . ( $state_hr // 'undef' )
        if !defined $state_hr || ref $state_hr ne 'HASH';
    # Shall return {table=>[] variable=>[],true_if_empty=>0}

    my $return = GGP::Tools::Variables->new();

    if (exists $rule->{'facts'}->{table}) { # table means array not hash-index
      if ($vars->{true_if_empty}) {
        $return->{table} = $rule->{'facts'}->{table};
        $return->{variable} = $rule->{'facts'}->{variable};
        $return->{true_if_empty} = 0;
      } else { # no index and not first
        ...;
      }

    } else { #index and not first
      #TODO Do merge. change facts to hashes of hashes
      # $rule->{'facts'}->{commonkeys}->{unique vars}
      # merge with $vars
      $return->{true_if_empty} = 0;
      $return->{variable} = $vars->{variable};
      my $i = _max (values %{$return->{variable}});
#      warn "\$i=$i";
      for my $factcol( sort_by { $rule->{'facts'}->{variable}->{$_} } keys %{$rule->{'facts'}->{variable}}) {
          $i++;
          next if exists $return->{variable}->{$factcol};

          $return->{variable}->{$factcol}=$i;
      }
      $return->{table}=[];

      my @varcolids =        map{$vars->{variable}->{$_}}   map{$rule->{'facts'}->{':colindex'}->{$_}}
                sort {$a <=>$b } keys %{$rule->{'facts'}->{':colindex'}};


      for my $row (@{$vars->{table}}) {
        my $key = join';', map{$row->[$_]} @varcolids;
#        warn $key;
        if (exists $rule->{'facts'}->{$key}) {
            for my $subretrow(@{$rule->{'facts'}->{$key}}) {
                my $returnrow = dclone $row;
                push @$returnrow, @$subretrow;
                push @{$return->{table}}, $returnrow;
            }
        } else {
          #do nothing
        }
      }
#      warn Dumper $return;
#      die;
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
        #die Dumper @return;
        #if ($return[0][0] eq 'line') {
        #    warn Dumper $variables;
        #    die;
        #}
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

sub _max {
    my ($max, @vars) = @_;
    for (@vars) {
        $max = $_ if $_ > $max;
    }
    return $max;
}


=head1 AUTHOR

Slegga

=cut

1;

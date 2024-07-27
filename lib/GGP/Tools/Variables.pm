package GGP::Tools::Variables;
use strict qw(vars );
use warnings;
use autodie;
use List::MoreUtils qw(any none);
use Carp;
use Data::Dumper;
use Storable qw(dclone);
use GGP::Tools::Utils qw( hashify extract_variables logf);
use experimental 'signatures';

=encoding utf8

=head1 NAME

GGP::Tools::Variables - Compute variables

=head1 SYNOPSIS

 use GGP::Tools::Variables;
 use Data::Dumper;
 $vars = GGP::Tools::Variables->new();
 $vars->do_and( $self->true( $state_hr, $criteria->[0], $vars ) );
 print Dumper $var;

=head1 DESCRIPTION

Can not be a Moo object. Matches will be about 30% slower.
Instead test heavely.

Contain the variables for current line. Represented as a table
Can be true or false.

Internal variables are
varibles = hash ref key = variable name, value = order beginning with 0
tables = array ref of array ref with table data [rownumber][ordernumber]
true_if_empty = how to decide true 1 = true even if no rows 0 = false on no rows
linebool = arrayref of all lines 1 = keep 0 = remove line

=head1 METHODS

=cut

=head2 new



=cut


sub new($class_name) {
    my $self = {};
    $self->{table}         = [];    #contain current variable data for line
    $self->{variable}      = {};    #contain name as key and which column number in table
    $self->{true_if_empty} = 1;     #if not used yet variables shall be true i empty.
    $self->{linebool}      = [];    # value 1 = keep row 0 = remove row on do_and
    bless( $self, $class_name );
}

# =head2 reset
#
# Reset object for handling a new line
#
# =cut
#
# sub reset($self) {
#     $self->{table}         = [];
#     $self->{variable}      = {};
#     $self->{true_if_empty} = 1;
# }

=head2 get
    my $facts = $vars->get();

Return object table;

=cut

sub get($self) {
    my $true = $self->get_bool();
    return { table => $self->{table}, variable => $self->{variable}, true => $true };
}

=head2 table

=cut

sub table( $self ) {
  return $self->{table};
}

=head2 variable

=cut

sub variable( $self ) {
  return $self->{variable};
}


=head2 get_bool

Report if self is true or false.
If false stop calculate criteria.

=cut

sub get_bool($self) {
    my $return = $self->{true_if_empty};
    if ( !$return && @{ $self->{table} } ) {
        $return = 1;
    }
    return $return;
}

=head2 do_and

    $vars->do_and( $self->true( $state_hr, $criteria->[0], $vars ) );

Should be named and but that word is used.
Main sub. Shall make a x-product of current table and input table

=cut

sub do_and($self,$input) {
    confess "first row table is undef " if ( exists $self->{table}->[0] && !defined $self->{table}->[0] );

    if ( $input->{variable} eq 'true' ) {
        return;    #statement is true but have no variables.
    } elsif ( $input->{variable} eq 'false' ) {
        $self->{table}         = [];
        $self->{variable}      = {};
        $self->{true_if_empty} = 0;
        return;
    } elsif ($input->{variable} eq 'linebool') {
      for my $i ( reverse 0 .. $#{ $self->{table} } ) {
        next if $input->{linebool}->[$i]; #keep row
        splice(@{$self->{table}}, $i, 1); #remove row
      }
      return;
    }
    confess "input is undef" . Dumper $input if !exists $input->{table};
    if ( !@{ $self->{table} } && $self->{true_if_empty} == 0 ) {
        return;
    }

    if (   @{ $input->{table} }
        && ( keys %{ $input->{variable} } )
        && !@{ $input->{table}->[0] } == ( keys %{ $input->{variable} } ) )
    {
        logf( Dumper $self );
        logf( Dumper $input);
        confess "Number of columns and number of names is not equal " . @{ $input->{table} };
    }
    if ( @{ $input->{table} } == 0 ) {
        $self->{table}         = [];    #contain current variable data for line
        $self->{true_if_empty} = 0;
        return;
    } elsif ( @{ $self->{table} } == 0 ) {
        if ( $self->{true_if_empty} == 1 ) {
            $self->{table}    = $input->{table};
            $self->{variable} = $input->{variable};
        } else {                        #$self->{true_if_empty} == 0
            return;
        }
    } else {

        # compare variables. If none are equal then make x'ed product
        # Make new $self->{table}
        my @commonvars = ();
        my @uniqinputs = ();
        my @cvkeys     = sort { $input->{variable}->{$a} <=> $input->{variable}->{$b} } keys %{ $input->{variable} };
        my @variablekeys = keys %{ $self->{variable} };
        for my $cv (@cvkeys) {
            if ( any { $_ eq $cv } @variablekeys ) {
                push( @commonvars, $cv );
            } else {
                push( @uniqinputs, $cv );
            }
        }
        if ( !@commonvars ) {    #make crossed product
            my $i = @variablekeys;
            while ( my ( $key, $value ) = each( %{ $input->{variable} } ) ) {
                $self->{variable}->{$key} = $i + $value;
            }

            my $newtable = [];
            for my $crow ( @{ $self->{table} } ) {
                for my $irow ( @{ $input->{table} } ) {
                    my @tmparray = ( @$crow, @$irow );
                    push( @$newtable, \@tmparray );    #may work may not work but should work
                }
            }
            $self->{table} = $newtable;
        } else {    #the complex part merge 2 tables
            my $newtable = [];

            # loop thru current variable combination
            my $variable = $self->{variable};
            for my $sline ( @{ $self->{table} } ) {

                # loop thru input variable combination
                for my $iline ( @{ $input->{table} } ) {
                    my $false = 0;
                    for my $var (@commonvars) {

                        # compare if common variables is equal
                        if ( $sline->[ $variable->{$var} ] ne $iline->[ $input->{variable}->{$var} ] ) {
                            $false = 1;
                        }
                    }
                    if ( !$false ) {

                        # then add all variables and make a row in new table
                        my $newline = dclone($sline);
                        if (@uniqinputs) {
                            for my $uniqi (@uniqinputs) {
                                push( @$newline, $iline->[ $input->{variable}->{$uniqi} ] );
                            }
                        }
                        push( @$newtable, $newline );
                    }

                    # if not equal do notthing
                }

                # set newtable instead of current table
            }
            $self->{table} = $newtable;
            if (@uniqinputs) {
                my $variable = $self->{variable};
                my $i = keys %{ $variable };
                for my $uniqi (@uniqinputs) {
                    $variable->{$uniqi} = $i;
                    $i++;
                }
            }
        }
    }
    $self->{true_if_empty} = 0;
    confess "first row table is undef " if ( exists $self->{table}->[0] && !defined $self->{table}->[0] );
}


=head2 do_or

Do use only linebool to keep track of rows

###do and between false/remove instead of true/keep.

###This is like: and a b (or x y)

=cut

sub do_or($self, $tables_ar, $effect) {
    confess "first row table is undef " if ( exists $self->{table}->[0] && !defined $self->{table}->[0] );

    confess "Inputs is not an ARRAY " . Dumper $tables_ar if !ref $tables_ar eq 'ARRAY';

    # loop thru current variable combination and do a remove
    my @linebool;
    my @commonvars = ();
    my $return;
    #add data
    my $variable = $self->{variable};
    if ( $self->{'true_if_empty'} and ( !keys %{ $variable } || $variable eq 'true' ) ) {
        my $i       = 0;
        my @extrvar = extract_variables($effect);
        for my $tmpvar (@extrvar) {
            $variable->{$tmpvar} = $i;
            $i++;
        }
        $self->{'true_if_empty'} = 0;
        my @cvkeys;
        for my $tableset (@$tables_ar) {

            if ( ref $tableset ne 'HASH' ) {
                logf( Dumper $tables_ar );
                confess "Not a HASH ref \$tableset $tableset";
            }

            # handle one and one table.
            @cvkeys =
                sort { $tableset->{variable}->{$a} <=> $tableset->{variable}->{$b} } keys %{ $tableset->{variable} };
            my @variablekeys = keys %{ $variable };
            for my $cv (@cvkeys) {
                if ( any { $_ eq $cv } @variablekeys ) {
                    push( @commonvars, $cv );
                } else {
                    logf( Dumper $self );
                    logf( Dumper $tables_ar );
                    logf( "\$cv: " . $cv );
                    logf( Dumper $variable );
                    confess "No unique rows in or statments";
                }
            }

            # handle one and one table.
            for my $tablerow ( @{ $tableset->{table} } ) {
                my $newline;

                #build neline
                for my $cvar (@commonvars) {
                    push( @$newline, $tablerow->[ $tableset->{variable}->{$cvar} ] );
                }

                push( @{ $self->{table} }, $newline );
            }
        }

        #substract data

    } else {

        for my $tableset (@$tables_ar) {
            if ( ref $tableset ne 'HASH' ) {
                confess "Not a HASH ref \$tableset $tableset";
            }
            if ($tableset->{variable} ne 'linebool') {
                confess "Not supported yet";
            }

            if (! @linebool) {
                @linebool = @{ $tableset->{linebool} };
            } else {
                for my $i(0 .. $#linebool) {
                    if (! $linebool[$i] ) {
                        $linebool[$i] = $tableset->{linebool}->[$i];
                    }
                }
            }
        }
    }

    # Get all false rows

    # at end remove false rows.

    # do_and removes the lines of us
    $return->{variable}='linebool';
    $return->{linebool}=\@linebool;
    # for my $i ( reverse 0 .. $#linebool ) {
    #     next if $linebool[$i];    # do not remove true
    #     splice( @{ $self->{table} }, $i, 1 );
    # }
    return $return;
}

=head2 distinct

Remove lines in variables
Go through the table and remove lines where [variable] is like [remove]
return a linebool type of object

=cut

sub distinct($self, $inputs) {
    my $return;
    $return->{table}    = [];
    $return->{variable} = 'linebool';
    $return->{linebool}    = [];
    my $variable = shift(@$inputs);
    my $remove   = shift(@$inputs);
    my $variabletmp = $self->{variable};

    confess "First argument of distinct must be a variable:" . Dumper $variable if $variable !~ /^\?\w/;

    if ( $remove !~ /^\?\w/ ) {
        my $col = $variabletmp->{$variable};
        for my $i ( 0 .. $#{ $self->{table} } ) {
            my $value = $self->{table}->[$i]->[$col];
            confess "ERROR: \$value is undef\n" . Dumper $self if !defined $value;
            $return->{linebool}->[$i] = $value eq $remove ? 0 : 1;
        }
    } else {
        my $rcol = $variabletmp->{$remove};
        my $col = $variabletmp->{$variable};
        for my $i ( 0 .. $#{ $self->{table} } ) {
            my $value = $self->{table}->[$i]->[$col];
            $return->{linebool}->[$i] = $self->{table}->[$i]->[$rcol] eq $value ? 0 : 1;
        }
    }

    #FUNCTION MUST RETURN SOMETHING
    #RETURN A TABLE OF ONE VARIABLE $return->{variable}->{}
    return $return;
}

=head1 AUTHOR

Slegga

=cut

1;

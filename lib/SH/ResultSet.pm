package SH::ResultSet;
use strict qw(vars );
use warnings;
use autodie;
use List::MoreUtils qw(any first_index none );
use Exporter 'import';
use Carp;
use utf8;
our @EXPORT_OK =
    qw(rs_aggregate rs_pretty_format_table rs_expand_column rs_add_aggr_column rs_remove_commonvalued_columns rs_merge rs_fill_missing_cols
    rs_convert_from_hashes );

=encoding utf8

=head1 NAME

SH::ResultSet.pm- For formatting a typically resultset from a query taken from a database.


=head1 VERSION

0.01

=head1 SYNOPSIS

    use SH::ResultSet qw (rs_aggregate rs_pretty_format_table);
    my $rs={data=>[['text1',10,20], ['text2',30,40]],columns=>['text','num1','num2']};
    $rs = rs_aggregate($rs,{aggregation=>{'text'=>'concat','num1'=>'sum','num2'=>'sum'}});
    print rs_pretty_format_table($rs);

=head1 DESCRIPTION

Is based on a resultset that is defined as an hash with a 'data' key and a 'columns' key. This define a table.
The method in this module transform or present this table/resultset in different way.


=head1 METHODS

=head2 rs_aggregate

    Lazy implementation. Just implement what is needed. Try to define API flexible

    input:
        resultset
        params as hash ref

    Where params = {
        aggregation=>{colname=>'sum|concat'}
        ,group_by=>[col1,col2]
        ,members=>{col1=>[none => 'YES']}
        ,concatsep=>','
    }

    Calculates a aggregated result. In first place sum columns in an resultset

    return:
        a resultset {data =>data_ar_ar,columns=>columnname_ar}

=cut

sub rs_aggregate {
    my $resultset_hr = shift;
    my $params_hr    = shift;
    my %lparams      = %$params_hr;
    my $lparams_hr   = \%lparams;
    confess("2. argument is not a hash ref") if !ref $lparams_hr eq 'HASH';
    for my $key ( keys %$lparams_hr ) {
        if ( $key !~ /(?:aggregation|members|concatsep|group_by)/ ) {
            confess( "Not a legal type must be aggregation|members|concatsep|group_by is " . ( $key // 'undef' ) );
        }
    }
    my @columns = @{ $resultset_hr->{columns} };
    my %result;
    my $return_hr   = {};
    my @groups      = ();
    my @falsegroups = ();
    my $separator   = "\b";
    if ( exists $lparams_hr->{'group_by'} ) {

        for my $search ( @{ $lparams_hr->{'group_by'} } ) {
            push( @groups, first_index { my $tmp = $_; uc $tmp eq uc $search } @columns );
        }
    }

    # check for valid columns for aggregation
    if ( exists $lparams_hr->{aggregation} and %{ $lparams_hr->{aggregation} } ) {
        for my $colname ( keys %{ $lparams_hr->{aggregation} } ) {
            confess("Can't find aggregated column in input resultset. $colname")
                if none { my $tmp = $_; uc $colname eq uc $tmp } keys %{ $lparams_hr->{aggregation} };
        }
    }

    for my $row ( @{ $resultset_hr->{data} } ) {
        my $group = join( $separator, @$row[@groups] ) || '_NONE_';
        for my $c ( 0 .. $#columns ) {
            if ( exists $lparams_hr->{members}->{ $columns[$c] } ) {
                if (   $lparams_hr->{members}->{ $columns[$c] }->[0] eq 'none'
                    && $row->[$c] eq $lparams_hr->{members}->{ $columns[$c] }->[1] )
                {
                    push @falsegroups, $group;
                }
            }
            if ( exists $lparams_hr->{aggregation}->{ $columns[$c] } ) {
                if ( lc $lparams_hr->{aggregation}->{ $columns[$c] } eq 'sum' ) {
                    $result{$group}{ $columns[$c] } += ( $row->[$c] // 0 );
                } elsif ( lc $lparams_hr->{aggregation}->{ $columns[$c] } eq 'concat' ) {
                    $result{$group}{ $columns[$c] } .= (
                        defined $result{$group}{ $columns[$c] }
                        ? ( $lparams_hr->{concatsep} // '' ) . $row->[$c]
                        : $row->[$c]
                    );
                }
            }
            if ( !defined $result{$group} ) {
                $result{$group} = undef;    # register group even when there is no aggregstion
            }
        }
    }
    if (@falsegroups) {
        delete $result{$_} for @falsegroups;
    }

    #Prepare resultset;
    if ( @groups == 0 ) {
        my $i = 0;
        for my $column (@columns) {
            if ( exists $result{'_NONE_'}{$column} ) {
                $return_hr->{data}->[0]->[$i] = $result{'_NONE_'}{$column};
                $return_hr->{columns}->[$i] = $column;
                $i++;
            }
        }
    } else {
        my $j = 0;
        for my $group ( sort keys %result ) {
            my $i = 0;
            my @gr_vals = split( $separator, $group );
            for my $grval (@gr_vals) {
                $return_hr->{data}->[$j]->[$i] = $grval;
                $return_hr->{columns}->[$i] = $columns[ $groups[$i] ];
                $i++;
            }
            for my $column (@columns) {
                if ( exists $result{$group}{$column} ) {
                    $return_hr->{data}->[$j]->[$i] = $result{$group}{$column};
                    $return_hr->{columns}->[$i] = $column;
                    $i++;
                }
            }
            $j++;
        }
    }
    return $return_hr;
}

=head2 rs_pretty_format_table

    input: resultset(data=>[row]->[col],columns=>[colname1,colname2,colname3 etc])
    optional params_hr: {
        columns=>[colname2,colname3],
        colformat=>{colname2=>"%04d"}
    }
    return variable containing a pretty formatted table.
    columnlength{columnname_uc}=[-]length
    TODO: cut columns if longer than columnlength

=cut

sub rs_pretty_format_table {    #[$query_handle], [$columnlength_href]
                                #confess('Expected 1 argument got '.scalar @_ ) if (none {$_ == @_} (1,2));
    my $resultset_hr = shift;
    my $params_hr    = shift;
    my %columnlength;
    confess( "Not a hash reference $resultset_hr = " . ( $resultset_hr // 'undef' ) ) if ref $resultset_hr ne 'HASH';
    my %columnnames        = ();
    my @columnorder        = ();
    my $columnnameslastnum = 0;
    my @tmpresult          = ();
    my $undef              = '[NULL]';
    if ( defined $params_hr && exists $params_hr->{columns} ) {

        for my $col ( @{ $params_hr->{columns} } ) {
            $columnnames{$col} = first_index { $_ eq $col } @{ $resultset_hr->{'columns'} };
        }
        @columnorder = @{ $params_hr->{columns} };
    } else {
        @columnnames{ @{ $resultset_hr->{'columns'} } } = ( 0 .. $#{ $resultset_hr->{'columns'} } );    #make index hash
        @columnorder = @{ $resultset_hr->{'columns'} };
    }
    if ( defined $params_hr && exists $params_hr->{null} ) {
        $undef = $params_hr->{null};
    }
    $columnnameslastnum = ( keys %columnnames ) - 1;
    %columnlength       = %{ $resultset_hr->{columnlengths} }
        if ( exists $resultset_hr->{columnlengths} && defined $resultset_hr->{columnlengths} );
    my $return = "\n";
    return $return if !exists $resultset_hr->{data};
    return $return if !exists $resultset_hr->{columns};
    if ( @{ $resultset_hr->{data} } ) {

        # minium column size is column header
        foreach my $colname ( keys %columnnames ) {
            if ( !exists $columnlength{$colname} ) {
                $columnlength{$colname} = length($colname);
                my $type = -1;
                foreach my $r ( 0 .. $#{ $resultset_hr->{data} } ) {
                    my $format = "%s ";
                    if ( defined $params_hr && exists $params_hr->{colformat} && exists $params_hr->{colformat}->{$colname} ) {
                        $format = $params_hr->{colformat}->{$colname} . ' ';
                    }
                    if ( defined $resultset_hr->{data}->[$r]->[ $columnnames{$colname} ] ) {
                        $tmpresult[$r][ $columnnames{$colname} ] = sprintf $format,
                            ( $resultset_hr->{data}->[$r]->[ $columnnames{$colname} ] );
                    }
                    $type = 1
                        if ( defined $tmpresult[$r][ $columnnames{$colname} ]
                        && $tmpresult[$r][ $columnnames{$colname} ] =~ /^\s*-?\d+\.?\d*\s*$/ );
                    $tmpresult[$r][ $columnnames{$colname} ] = "$undef " if !defined $tmpresult[$r][ $columnnames{$colname} ];
                    my $l = length( $tmpresult[$r][ $columnnames{$colname} ] );
                    $columnlength{$colname} = $l if $columnlength{$colname} < $l;
                }
                $columnlength{$colname} = $type * $columnlength{$colname};
            }
        }

        $return .= " " . join( '', map { my $tmp = $_; sprintf( "%*s ", $columnlength{$tmp}, uc($tmp) ) } @columnorder );
        $return .= "\n ";
        $return .= join( '', map { my $tmp = $_; sprintf( "%*s ", $columnlength{$tmp}, '-' x length $tmp ) } @columnorder );
        $return .= "\n ";
        foreach my $r ( 0 .. $#{ $resultset_hr->{data} } ) {
            foreach my $colname (@columnorder) {
                my $space = ' ' x ( abs( $columnlength{$colname} ) - length( $tmpresult[$r][ $columnnames{$colname} ] ) + 1 );
                if ( $columnlength{$colname} > 0 ) {
                    $return .= $space . $tmpresult[$r][ $columnnames{$colname} ];
                } else {
                    $return .= $tmpresult[$r][ $columnnames{$colname} ] . $space;
                }

            }
            $return .= "\n ";
        }
    }
    return $return;
}

=head2 html_format_table_from_resultset

UNDER CONSTRUCTION

=cut

sub html_format_table_from_resultset {    #[$query_handle], [$columnlength_href]
    my $resultset_hr = shift;

    my @columnnames = map { uc $_ } @{ $resultset_hr->{columns} };
    my $return = "\n";
    if ( @{ $resultset_hr->{data} } ) {
        if (@columnnames) {

            # minium column size is column header

            $return .= "<td>" . join( '</td><td>', @columnnames );
            $return .= "<\tr><tr>";
            $return .= "\n ";
            foreach my $r ( 0 .. $#{ $resultset_hr->{data} } ) {
                foreach my $c ( 0 .. $#columnnames ) {
                    $return .= ( $resultset_hr->{data}->[$r]->[$c] // '[NULL]' ) . ( $c < $#columnnames ? '</td><td>' : '' );
                }
                $return .= "\n ";
            }
        }
    }
    $return = '<table class="list">
<tr>' . $return . '</tr>
</table>';

    $return;
}

=head2 rs_remove_commonvalued_columns

return a resultset where columns the value of the resultset is equal is removed.

=head3 test

 nx-mysql
 echo "select * from tnet_Interface where id in (6026197,6026198,6026199,6026200)"|perl -Ilib script/sql_not_show_similar_valuedcolumns.pl

=cut

sub rs_remove_commonvalued_columns {
    my $resultset = shift;
    confess "\$resultset is undef" if !defined $resultset;
    confess "Not hash ref \$resultset = " . $resultset . ' ref:' . ref $resultset if ref $resultset ne 'HASH';
    my @columns = @{ $resultset->{columns} };
    my @rows    = @{ $resultset->{data} };
    my @return_cols;    # columnnames that differ
    my $return  = {};   # equal line
    my $return2 = {};   # diffed column
    return $return,    $return2 if !@rows;
    return $resultset, $return2 if @rows == 1;
    my @commonval;

COLUMNS:
    for my $c ( 0 .. $#columns ) {
        my $lastval;
    ROWS:
        for my $r ( 0 .. $#rows ) {
            if ( !defined $lastval && $r == 0 ) {
                $lastval = $rows[$r][$c];
                next;
            } elsif ( defined $rows[$r][$c] != defined $lastval || ( defined $lastval && $lastval ne $rows[$r][$c] ) ) {
                push( @return_cols, $c );
                next COLUMNS;
            }
        }
        push( @commonval, $c );
    }
    for my $i ( 0 .. $#return_cols ) {
        push( @{ $return->{columns} }, $columns[ $return_cols[$i] ] );
    }
    for my $i ( 0 .. $#commonval ) {
        push( @{ $return2->{columns} }, $columns[ $commonval[$i] ] );
    }
    for my $r ( 0 .. $#rows ) {
        my $new_row;
        for my $i ( 0 .. $#return_cols ) {
            push( @{$new_row}, $rows[$r][ $return_cols[$i] ] );
        }
        push( @{ $return->{data} }, $new_row );
    }

    #Get commonvalued columns values
    my $new_row;
    for my $i ( 0 .. $#commonval ) {

        #next if (any {$i == $_} @return_cols);
        push( @{$new_row}, $rows[0][ $commonval[$i] ] );
    }
    push( @{ $return2->{data} }, $new_row );

    return $return, $return2;
}

=head2 rs_expand_column

Expand the resultset with the values of a given column.

i.e:

Start:
$rs={data=>[[2013,'ok',1][2014,'err',2]],columns=>['stays','expand','value']}
rs_expand_column($rs,'expand','value',{'ok'=>0,'err'=>1}

Transform to:

{data=>[[2013,1,0][2014,'err',0,2]],columns=>['stays','ok','err']}

Normally used with a call of rs_aggregate and the group_by parameter after first calling rs_expand_column

=cut

sub rs_expand_column($$$$) {
    my $resultset         = shift;
    my $expandcol         = shift;
    my $valuecol          = shift;
    my $columndefaults_hr = shift;
    confess "To many params @_" if @_;
    my $return_rs = {};

    # figure out new colmnset
    my @unchangedcols = grep { $_ !~ /^($expandcol|$valuecol)$/ } @{ $resultset->{columns} };
    $return_rs->{columns} = \@unchangedcols;
    push @{ $return_rs->{columns} }, ( keys %$columndefaults_hr );
    my $expcolno = first_index { $_ eq $expandcol } @{ $resultset->{columns} };
    my $valcolno = first_index { $_ eq $valuecol } @{ $resultset->{columns} };
    my @newcols  = ();
    for my $i ( 0 .. $#{ $resultset->{data} } ) {
        if ( none { $_ eq $resultset->{data}->[$i]->[$expcolno] } @{ $return_rs->{columns} } ) {
            push @newcols, $resultset->{data}->[$i]->[$expcolno];
        }
    }
    push @{ $return_rs->{columns} }, @newcols;

    # add values
    my %retcolnos = ();
    for my $i ( 0 .. $#{ $return_rs->{columns} } ) {
        $retcolnos{ $return_rs->{columns}->[$i] } = $i;
    }
    for my $i ( 0 .. $#{ $resultset->{data} } ) {
        for my $colname ( @{ $return_rs->{columns} } ) {
            my $untcol = first_index { $_ eq $colname } @{ $resultset->{columns} };
            if ( defined $untcol && $untcol >= 0 ) {
                $return_rs->{data}->[$i]->[ $retcolnos{$colname} ] = $resultset->{data}->[$i]->[$untcol];
            } elsif ( $colname eq $resultset->{data}->[$i]->[$expcolno] ) {
                $return_rs->{data}->[$i]->[ $retcolnos{$colname} ] = $resultset->{data}->[$i]->[$valcolno];
            } elsif (
                any {
                    $_ eq $colname;
                }
                ( keys %$columndefaults_hr )
                )
            {
                $return_rs->{data}->[$i]->[ $retcolnos{$colname} ] = $columndefaults_hr->{$colname};
            } else {
                confess "I do not know what to do with column: " . ( $colname // '[undef]' );
            }
        }
    }
    return $return_rs;
}

=head2 rs_add_aggr_column

Add an aggregated/callculated column to the resultset.
The calculation accept column-name as a parameter. This will be eval'ed so perl code is ok.
i.e.
rs_add_aggr_column($rs,{total=>'ok+err',average=>'(ok+err)/2',minimum=>'ok<err?ok:err'})

=cut

sub rs_add_aggr_column {
    my $rs           = shift;
    my $aggrcols_hr  = shift;
    my %tmp          = %$rs;
    my $return_rs    = \%tmp;
    my %calculations = ();
    while ( my ( $colname, $calculation ) = each(%$aggrcols_hr) ) {
        my $newcalculation = 'sub { my ($rs,$ch)=@_;my $ret=';
        foreach my $word ( split( /\b/, $calculation ) ) {
            if ( any { my $tmp = $_; uc $word eq uc $tmp } @{ $rs->{'columns'} } ) {

                #$_[0] = $rs->{data}->[currow]  , $_[1] = \%columns
                #warn $word;
                my $num = '$rs->[$ch->{' . ($word) . '}]';

                #                 my $tmpcode = eval 'sub {'.$num.'}';
                #                 print
                $newcalculation .= $num;

                # $newcalculation .= 'print "'.$word.'";';
            } else {
                $newcalculation .= $word;
            }
        }
        $newcalculation .= ';return $ret}';
        $calculations{$colname} = $newcalculation;
        push @{ $return_rs->{columns} }, $colname;
    }

    #get values
    my %columns;
    @columns{ @{ $rs->{'columns'} } } = ( 0 .. $#{ $rs->{'columns'} } );    #make index hash
                                                                            #warn Dumper %columns;
    for my $i ( 0 .. $#{ $return_rs->{data} } ) {
        for my $calccol ( keys %calculations ) {

            #            warn $calculations{$calccol},Dumper $rs->{data}->[$i];
            my $code = eval $calculations{$calccol};
            if ( !defined $code ) {
                confess "eval 1 error: $@\nTry to eval: $calculations{$calccol}\n\$calccol: $calccol\n";
            }
            $rs->{data}->[$i]->[ $columns{$calccol} ] = $code->( $rs->{data}->[$i], \%columns );

        }
    }

    return $return_rs;
}

=head2 rs_merge

Return an merged resultset.
Input: A number of resultset that is going to be merged to the return resultset.

First rs decide order.


=cut

sub rs_merge {
    my @rsinn = @_;
    my $rsreturn;
    for my $rs (@rsinn) {
        if ( !defined $rsreturn ) {
            my %tmprs = %{$rs};
            $rsreturn = \%tmprs;
        } else {
            my $firstnewrow = $#{ $rsreturn->{data} } + 1;
            my $i           = $#{ $rs->{columns} };
            my $lastidx     = $i;
            for my $ccol ( reverse @{ $rs->{columns} } ) {

                my $fidx = first_index { $_ eq $ccol } @{ $rsreturn->{columns} };
                if ( !defined $fidx ) {
                    splice( @{ $rsreturn->{columns} }, $lastidx + 1, 0, $ccol );
                    for my $j ( reverse 0 .. $#{ $rsreturn->{data} } ) {
                        splice( @{ $rsreturn->{data}->[$j] }, $lastidx + 1, 0, undef );
                    }
                }
                $lastidx = $fidx;
                $i--;
            }
            for my $r ( 0 .. $#{ $rs->{data} } ) {

                # legg inn et og et felt i $rereturn

                # loop igjennom feltene til $rsreturn og populer en og en rad
                my $j = 0;
                for my $col ( @{ $rsreturn->{columns} } ) {
                    my $value;
                    my $ocidx = first_index { lc $_ eq lc $col } @{ $rs->{columns} };
                    if ( $ocidx >= 0 ) {
                        $value = $rs->{data}->[$r]->[$ocidx];
                    }
                    $rsreturn->{data}->[ $firstnewrow + $r ]->[$j] = $value;
                    $j++;
                }
            }
        }

    }
    return $rsreturn;
}

=head2 rs_fill_missing_cols

Return a resultset with the columns of the first given rs and data from the last given rs.

=cut

sub rs_fill_missing_cols {
    my $template_rs = shift;
    my $data_rs     = shift;
    my $return_rs;
    $return_rs->{columns} = $template_rs->{columns};
    for my $r ( 0 .. $#{ $data_rs->{data} } ) {
        my $i = 0;
        for my $t_col ( @{ $template_rs->{columns} } ) {
            my $value;
            my $idx = first_index { lc $_ eq lc $t_col } @{ $data_rs->{columns} };
            if ( $idx >= 0 ) {
                $value = $data_rs->{data}->[$r]->[$idx];
            }
            $return_rs->{data}->[$r]->[$i] = $value;
            $i++;
        }
    }
    return $return_rs;
}

=head2 rs_convert_from_hashes

Takes a data structure which is an array of hashes.
and a list (array ref) of columns that should be placed first in the given order.
Loop through the keys of the hashes and register the keys as columnname

Return a resultset data structure

=cut

sub rs_convert_from_hashes {
    my $data      = shift;
    my $colsfirst = shift;

    # get the columnnames
    my @cols = ();

    for my $line (@$data) {
        for my $key ( keys %$line ) {
            if ( none { $key eq $_ } @cols ) {
                push( @cols, $key );
            }
        }
    }

    # order columns
    if ($colsfirst) {
        my @newcolorder = ();
        for my $coln (@$colsfirst) {
            if ( any { $coln eq $_ } @cols ) {
                push( @newcolorder, $coln );
                my $idx = first_index { $coln eq $_ } @cols;
                splice( @cols, $idx, 1 );
            }
        }
        unshift( @cols, @newcolorder );
    }

    my $return_rs;
    $return_rs->{columns} = \@cols;

    # get the data

    my $i = 0;

    #    print Dumper $return_rs;
    for my $line (@$data) {
        while ( my ( $key, $value ) = each(%$line) ) {
            my $idx = first_index { lc $_ eq lc $key } @{ $return_rs->{columns} };
            $return_rs->{data}->[$i]->[$idx] = $value;
        }
        $i++;
    }
    return $return_rs;
}

=head1 AUTHOR

Slegga - C<slegga@gmail.com>

=cut

1;

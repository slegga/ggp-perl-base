package SH::Table;
use Carp;
use Data::Dumper;
use autodie;
use strict;
use warnings;
use Text::CSV; #::Encoded;
use File::Copy;
use List::Util qw(max);
use List::MoreUtils qw(uniq none);
use YAML::Syck ();
use Scalar::Util qw(looks_like_number);

my $homedir;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";

use SH::Script qw(ask);

# use File::Slurp qw(read_file write_file);

our $directory;

=encoding utf8

=head1 NAME

SH::Table - Very simple database file. One file one table.

=head1 SYNOPSIS

    use SH::Table;
    $SH::Table::directory='/tmp';
    $test=SH::Table->new($testfile,{columnseparator=>";"});
    #control file
    $passwords->control();
    $passwords->show();

=head1 DESCRIPTION

Read and store table like data in a csv likely file.
One object represent a table.

=head1 VARIABLES

    $SH::Table::directory must be set before new is called. It is the root of the data area.

=head1 METHODS

=head2 new

    my $object_instance = new(class_name)
    Constructor

    Options:

    noheader:           ?
    utf8:               Data is stored as utf8
    columnseparator:    Default is ',' Set columnseparator in stored data files
    eol:                End of line 'line separator'
=cut

sub new {
    my ( $class_name, $table_name, $options ) = ( shift, shift, shift );
    confess "Pleas set SH::Table::\$directory before using this object" if !defined $directory;
    my $self;
    $self->{table} = $table_name;
    my $filepathbase = "$directory/$table_name";
    $self->{file}    = "$filepathbase.csv";
    $self->{deffile} = "$filepathbase.def";

    #SET DEFAULTS
    $self->{config}->{noheader}        = 0;
    $self->{config}->{utf8}            = 0;
    $self->{config}->{columnseparator} = ',';

    # LOAD OPTIONS
    if ( -f $self->{deffile} ) {
        open my $fh, '<', $self->{deffile} or die "Failed to read " . $self->{deffile} . ": $!";
        $self->{config} = YAML::Syck::Load(
            do { local $/; <$fh> }
        );    # slurp content
        close $fh;
    }
    if ( exists $options->{noheader} ) {
        $self->{config}->{noheader} = $options->{noheader};
    }
    if ( exists $options->{utf8} ) {
        $self->{config}->{utf8} = $options->{utf8};
    }
    if ( exists $options->{columnseparator} ) {
        $self->{config}->{columnseparator} = $options->{columnseparator};
    }

    # LOAD DATA
    # my %csvopts={};

    $self->{parser} = Text::CSV->new( { sep_char => $self->{config}->{columnseparator} } );    #,encoding  => "utf8" ::Encoded
    if ( $options->{eol} ) {
        warn "eol set";
        $self->{parser}->eol( $options->{eol} );
        $/ = $options->{eol};
    } else {
  #      $/ = "\n"; #use this as default
    }

    confess "Can't find file!. $self->{file}" if !-f $self->{file};
    my $utf8 = '';
    if ( $self->{utf8} ) {
        use open qw( :encoding(UTF-8) :std );
        $utf8 = ':encoding(UTF-8)';
    }
    open( my $fh, '<' . $utf8, $self->{file} );
    for my $line (<$fh>) {
        chomp $line;
        next if ( !defined $line );
        if ( $self->{parser}->parse($line) ) {
            my @linedata = $self->{parser}->fields();

            #            next if (! $linedata[0]);
            #        print $line;
            if ( !exists $self->{columns} ) {
                if ( $self->{noheader} ) {
                    my @tmp = ( 0 .. $#linedata );
                    $self->{columns} = \@tmp;
                    push( @{ $self->{data} }, \@linedata );
                } else {    #with headers
                    $self->{columns} = \@linedata;
                }
            } else {
                push( @{ $self->{data} }, \@linedata );
            }
        } else {
            $self->{parser}->error_diag();
            warn "Line could not be parsed: $line\n";
        }
    }
    $self->{lineno} = 0;
    if ( $self->{noheader} ) {
        $self->{noofcolumns} = @{ $self->{data}->[0] };
    } else {
        $self->{noofcolumns} = @{ $self->{columns} };
    }

    $self->{autocommit} = $options->{autocommit} // 1;
    my %columnno;
    my $counter = 0;
    for my $column ( @{ $self->{columns} } ) {
        $columnno{$column} = $counter;
        $counter++;
    }
    $self->{columnno} = \%columnno;
    close($fh);
    bless( $self, $class_name );
    return $self;
}

=head2 show

Show/print rows

=cut

sub show {
    my $self       = shift;
    my $rownum_ar  = shift;
    my $columns_ar = shift;
    my $where_hr   = shift;
    my $args_hr    = shift;    # {showrownum=>1 turn on showing row number}

    confess 'Expected 0-1 argument got ' . scalar @_ if ( @_ > 1 );
    my %columnlength;

    #  confess "Not a hash reference $self = ".($self//'undef') if ref $self ne 'HASH';
    my @chosencols = ();

    if ( defined $columns_ar && ref $columns_ar eq 'ARRAY' && @$columns_ar ) {
        @chosencols = @$columns_ar;
    } else {
        @chosencols = @{ $self->{columns} };
    }
    my @columnnames = map { uc $_ } @{ $self->{columns} };
    %columnlength = %{ $self->{columnlengths} } if ( exists $self->{columnlengths} && defined $self->{columnlengths} );
    my $return = "\n";
    return $return if !exists $self->{data};
    my @data = $self->where($where_hr);
    my @rows;
    if (@data) {

        if (@columnnames) {

            # minium column size is column header
            if ( ref $rownum_ar eq 'ARRAY' ) {
                @rows = @$rownum_ar;
            } else {
                @rows = 0 .. $#data;
            }
            foreach my $c ( 0 .. $#columnnames ) {
                if ( !exists $columnlength{ $columnnames[$c] } ) {
                    $columnlength{ $columnnames[$c] } = length( $columnnames[$c] );
                    my $type = -1;
                    foreach my $r (@rows) {
                        my $e = $data[$r][$c];
                        $type = 1 if ( defined $e && $e =~ /^-?\d+\.?\d*$/ );
                        $e = "[NULL]" if !defined $e;
                        my $l = length($e);
                        $columnlength{ $columnnames[$c] } = $l if $columnlength{ $columnnames[$c] } < $l;
                    }
                    $columnlength{ $columnnames[$c] } = $type * $columnlength{ $columnnames[$c] };
                }
            }

            $return .= ( $args_hr->{showrownum} ? ' ROW#' : '' ) . " "
                . join( '', map { sprintf( "%*s ", $columnlength{ uc $_ }, uc($_) ) } @chosencols );
            $return .= "\n ";
            $return .= ( $args_hr->{showrownum} ? '---- ' : '' )
                . join( '', map { sprintf( "%*s ", $columnlength{ uc $_ }, '-' x length $_ ) } @chosencols );
            $return .= "\n ";
            foreach my $r (@rows) {
                $return .= ( $args_hr->{showrownum} ? sprintf( "%4d ", $r ) : '' );
                foreach my $c ( 0 .. $#{ $data[$r] } ) {
                    next if none { lc $columnnames[$c] eq lc $_ } @chosencols;
                    $return .= sprintf "%*s ", ( $c <= $#columnnames ? $columnlength{ $columnnames[$c] } : 30 ),
                        ( $data[$r][$c] // '[NULL]' );
                }
                $return .= "\n ";
            }
        }
    }
    print $return;
    return @rows;
}

=head2 show_regexp

Examine all fields and match against regexp. Regexp has to match a field value. Not the whole line

=cut

sub show_regexp {
    my $self           = shift;
    my $regexp         = shift;
    my $choosencols_ar = shift;
    my $args_hr        = shift;
    my @return         = ();
    for my $r ( 0 .. $#{ $self->{data} } ) {
        for my $value ( @{ $self->{data}->[$r] } ) {

            # warn $value;
            if ( $value =~ /$regexp/i ) {
                push( @return, $r );
                last;
            }
        }
    }

    return $self->show( \@return, $choosencols_ar, undef, $args_hr );
}

=head2 where

Examine all rows if qualified by the where statement
return only rows which is qualified

=cut

sub where {
    my $self     = shift;
    my $where_hr = shift;
    my @return;

    my %fields;
    @fields{ @{ $self->{columns} } } = ( 0 .. $#{ $self->{columns} } );

    for my $r ( 0 .. @{ $self->{data} } ) {
        my $ok = 1;
        for my $key ( keys %$where_hr ) {
            confess "Invalid column in where $key" if ( !exists $fields{$key} );
            my $tmp = $where_hr->{$key};
            if ( $self->{data}->[$r]->[ $fields{$key} ] !~ /$tmp/ ) {
                $ok = 0;
            }
        }
        push @return, $self->{data}->[$r];
    }
    return @return;
}

=head2 showrow

MySQL like \G
one column field at each row. key: value

=cut

sub showrow {
    my $self       = shift;
    my $rowno      = shift;
    my $options_hr = shift;
    my $maxcol     = scalar @{ $self->{columns} };
    my $maxrow     = scalar @{ $self->{data}->[$rowno] };
    my $max        = max( $maxcol, $maxrow );
    for my $i ( 0 .. ( $max - 1 ) ) {
        if ( $options_hr->{numerate} ) {
            printf "%-2s:  ", $i;
        }
        if ( $i < $maxcol && $i < $maxrow ) {
            printf "%-20s: %s\n", $self->{columns}->[$i], $self->{data}->[$rowno]->[$i];
        } elsif ( $i >= $maxcol ) {
            printf "undef: %s\n", $self->{data}->[$rowno]->[$i];
        } else {
            printf "%-20s: [NULL]\n", $self->{columns}->[$i];
        }
    }
}

=head2 control

Check that data matched the data definitions

=cut

sub control {
    my $self = shift;
    confess 'Expected 0 argument got ' . scalar @_ if ( @_ != 0 );

    # CONTROL NUMBER OF COLUMNS
    my @columnnames = map { uc $_ } @{ $self->{columns} };
    my $tablecolno  = @columnnames;
    my @changedrows = ();
    confess "No data" if !exists $self->{data};
    foreach my $r ( 0 .. $#{ $self->{data} } ) {

        #   SJEKKER OM RADENE HAR RIKTIG LENGDE

        while (1) {
            my $rowcolno = scalar @{ $self->{data}->[$r] };
            if ( $tablecolno != $rowcolno ) {
                my $action = 's(L)ette';
                $action = '(L)egge til' if ( $tablecolno > $rowcolno );

                print "Forventer $tablecolno kolonner fikk $rowcolno.\n";
                $self->show( [$r] );

                my $answer = ask(
                    '(E)ditere rad ;=skilletegn eller ' . $action . ' innhold i kolonne',
                    [ 'e', 'l' ],
                    { 'remember' => 1 }
                );
                if ( $answer eq 'e' ) {
                    $self->editrow($r);
                } elsif ( $answer eq 'l' ) {
                    $self->showrow( $r, { numerate => 1 } );
                    my $delcol = ask( 'Hvilket nummer vil du ' . $action . ' 100=avbryt', qr/\d+/, { 'remember' => 1 } );
                    confess "Bruker avslutt" if $delcol == 100;
                    if ( $tablecolno < $rowcolno ) {
                        confess "Kolonnen finnes ikke" if $delcol >= $rowcolno;
                        splice( @{ $self->{data}->[$r] }, $delcol, 1 );
                    } elsif ( $tablecolno > $rowcolno ) {
                        confess "Kolonnen finnes ikke" if $delcol >= $tablecolno;
                        print "Innsatt verdi: ";
                        my $answer = <STDIN>;
                        chomp($answer);
                        splice( @{ $self->{data}->[$r] }, $delcol, 0, $answer );
                    }
                }
                push @changedrows, $r;
                next;
            }
            last;
        }

        # SJEKKER FELTREGLER
        for my $c ( 0 .. $#{ $self->{data}->[$r] } ) {
            my $colname = $self->{columns}->[$c];
            while (1) {
                my $coldata = $self->{data}->[$r]->[$c];
                if ( exists $self->{config}->{columndefs} && exists $self->{config}->{columndefs}->{$colname}->{filter} ) {
                    my $regexp = '^' . $self->{config}->{columndefs}->{$colname}->{filter} . '$';
                    if ( $coldata !~ /$regexp/ ) {
                        printf "\n\n'$coldata' tilfredstiller ikke regexp: %s for kolonne: %d %s\n", $regexp, $c,
                            $self->{columns}->[$c];
                        $self->show( [$r] );
                        my $answer = ask(
                            'Editere (r)ad ;=skilletegn, edidtere (k)olonne eller (b)ytte felt innhold med et annet felt',
                            [ 'r', 'k', 'b' ],
                            { 'remember' => 1 }
                        );
                        if ( $answer eq 'r' ) {
                            $self->editrow($r);
                        } elsif ( $answer eq 'k' ) {
                            $self->showrow( $r, { numerate => 1 } );
                            printf "Gammel verdi: %s\n", $self->{data}->[$r]->[$c];
                            print "Ny     verdi: ";
                            my $answer = <STDIN>;
                            chomp($answer);
                            splice( @{ $self->{data}->[$r] }, $c, 1, $answer );
                        } elsif ( $answer eq 'b' ) {
                            $self->showrow( $r, { numerate => 1 } );
                            my $delcol = ask(
                                'Hvilket kolonne nummer vil du bytte med '
                                    . $c . ' '
                                    . $self->{columns}->[$c]
                                    . ' (100=avbryt)',
                                qr/\d+/,
                                { 'remember' => 1 }
                            );
                            confess "Bruker avslutt" if $delcol == 100;
                            confess "Kolonnen finnes ikke" if $delcol >= $tablecolno;
                            my $tmpval = $self->{data}->[$r]->[$c];
                            $self->{data}->[$r]->[$c]      = $self->{data}->[$r]->[$delcol];
                            $self->{data}->[$r]->[$delcol] = $tmpval;
                        }
                        push @changedrows, $r;
                    } else {
                        last;
                    }
                } else {
                    last;
                }
            }
        }
    }
    if (@changedrows) {
        @changedrows = uniq( sort { $a <=> $b } @changedrows );
        $self->show( \@changedrows );
        ask( 'Commit ', ['y'] );
        $self->commit();
    }
}

=head2 newrow

Get data to new row from STDIN/user

=cut

sub newrow {
    my $self = shift;
    my $row  = [];
    for my $columnname ( @{ $self->{columns} } ) {
        $columnname = uc($columnname);
        print "$columnname: ";
        my $input = <STDIN>;
        chomp $input;
        push @$row, $input;
    }
    push @{ $self->{data} }, $row;
    $self->control();
    $self->commit();
}

=head2 editrow

Get data to an edited row from STDIN/user

=cut

sub editrow {
    my $self = shift;
    my $r    = shift;    #$r=row number
    if ( !defined $r ) {
        confess "Row number is not defined";
    }
    if ( !looks_like_number($r) ) {
        confess "Row number is not a number '$r'";
    }
    print "Kopier raden under og endre den. Ny rad vil bli slik du skriver den inn\n";
    print "Gammelt:  ", join( ';', @{ $self->{data}->[$r] } ), "\nNye data: ";
    my $innput = <STDIN>;
    chomp($innput);
    if ($innput) {
        my @tmp = split /\;/, $innput;
        $self->{data}->[$r] = \@tmp;
    }
}

#print Dumper $self;

=head2 fetchrow

Get next row from stream

=cut

sub fetchrow {
    my $self = shift;
    my @keys = @{ $self->{columns} };
    return if !exists $self->{data}->[ $self->{lineno} ];
    my @values = @{ $self->{data}->[ $self->{lineno} ] };
    my $return_hr;
    for my $i ( 0 .. $#keys ) {
        $return_hr->{ $keys[$i] } = $values[$i];
    }
    $self->{lineno}++;
    return $return_hr;
}

=head2 fetchlastline

Get last row

=cut

sub fetchlastline {
    my $self = shift;
    my @keys = @{ $self->{columns} };
    my $last = $#{ $self->{data} };
    return if !exists $self->{data}->[$last];
    my @values = @{ $self->{data}->[$last] };
    my $return_hr;
    for my $i ( 0 .. $#keys ) {
        $return_hr->{ $keys[$i] } = $values[$i];
    }
    return $return_hr;

}

=head2 fetchlinenum

Takes line number. Return row

=cut

sub fetchlinenum {
    my $self    = shift;
    my $linenum = shift;
    my @keys    = @{ $self->{columns} };
    return if !exists $self->{data}->[$linenum];

    #    print Dumper $self->{data}->[$linenum];
    my @values = @{ $self->{data}->[$linenum] };
    my $return_hr;
    for my $i ( 0 .. $#keys ) {
        $return_hr->{ $keys[$i] } = $values[$i];
    }
    return $return_hr;

}

=head2 getresultset

Return  the hole table as resultset

=cut

sub getresultset {
    my $self      = shift;
    my $return_hr = undef;
    $return_hr = { data => $self->{data}, columns => $self->{columns} };
    return $return_hr;
}

=head2 append

Put a line at the end of data file

=cut

sub append {
    my $self   = shift;
    my $row_hr = shift;
    confess( "first argument \$row_hr must be an HASH: " . ( $row_hr // '[NULL]' ) ) if ref $row_hr ne 'HASH';
    my @missingcolumns = grep { !exists $row_hr->{$_} } @{ $self->{columns} };
    confess( "Missed the following columns: " . join( ',', @missingcolumns ) ) if @missingcolumns;
    my @newline = map { $row_hr->{$_} } @{ $self->{columns} };

    #    my $push_ar=\@push;
    #  my $status = $csv->print($fh, $push_ar); # think og return value
    if ( $self->{autocommit} ) {
        open( my $fh, '>> :encoding(UTF-8)', $self->{file} );

        #    print Dumper @push;
        my $status  = $self->{parser}->combine(@newline);
        my $tmpline = $self->{parser}->string();
        print $fh "$tmpline\n";
        print "\$status=$status";

        # print $fh "\n";
        close($fh);
    }
    push( @{ $self->{data} }, \@newline );
    return \@newline;
}

=head2 unshift

Put a line at the beginning of data file

=cut

sub unshift {
    my $self   = shift;
    my $row_hr = shift;
    confess( "first argument \$row_hr must be an HASH: " . ( $row_hr // '[NULL]' ) ) if ref $row_hr ne 'HASH';
    my @missingcolumns = grep { !exists $row_hr->{$_} } @{ $self->{columns} };
    confess( "Missed the following columns: " . join( ',', @missingcolumns ) ) if @missingcolumns;
    my @newline = map { $row_hr->{$_} } @{ $self->{columns} };

    #    my $push_ar=\@push;
    #  my $status = $csv->print($fh, $push_ar); # think og return value
    if ( $self->{autocommit} ) {
        $self->commit();
    }
    unshift( @{ $self->{data} }, \@newline );
    return \@newline;
}

=head2 commit

Save memory object to data file

=cut

sub commit {
    my $self = shift;
    move( $self->{file}, '/tmp' );
    open my $fh, '> :encoding(UTF-8)', $self->{file};
    my $status = $self->{parser}->print( $fh, $self->{columns} );
    print $fh "\n";
    for my $row ( @{ $self->{data} } ) {
        $status = $self->{parser}->print( $fh, $row );
        print $fh "\n";
    }
    close $fh;
}

=head2 extract_hash

Takes a columnname for key and a columnname for value
Return an hash

=cut

sub extract_hash {
    my $self  = shift;
    my $key   = shift;
    my $value = shift;
    my %return_hr;
    my $counter = 0;
    my %columns = %{ $self->{columnno} };
    for my $r ( @{ $self->{data} } ) {
        $return_hr{ $r->[ $columns{$key} ] } = $r->[ $columns{$value} ];
    }
    return %return_hr;
}

=head2 fetch_reset

Reset the fetch stream. Next row which is fetched will be the first row

=cut

sub fetch_reset {
    my $self = shift;
    $self->{lineno} = 0;
}
1;

=head1 AUTHOR

Slegga

=cut


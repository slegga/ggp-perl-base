package GGP::Tools::Utils;
use List::Flatten;
use Carp;
use autodie;
use strict;
use warnings;
use Data::Dumper;
use Data::Compare;    #0= differ 1=equal
use Exporter 'import';
our @EXPORT_OK = qw( hashify extract_variables data_to_gdl store_result logf logdest logfile split_gdl cartesian);
use List::MoreUtils qw(any uniq first_index none);
use feature 'say';
my $homedir;


BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}


=encoding utf8

=head1 NAME

GGP::Tools::Utils

=head1 SYNOPSIS

 use GGP::Tools::Utils qw(hashify);
 use Data::Dumper;
 print hashify(['key','value']);

=head1 DESCRIPTION

Help functions for GGP programs.

=head1 FUNCTIONS

=cut

# use lib "$homedir/git/ggp-perl-base/lib";

#try to make global
{
    my $logdest;
    my $logfile;

=head2 logdest

Set log destination

=cut


    sub logdest {
        my $dest = shift;
        if ( !defined $logdest ) {
            $logdest = $dest // 'screen';
        }
        return $logdest;
    }

=head2 logfile

Set log file name

=cut

    sub logfile {
        my $dest = shift;
        if ( defined $dest ) {
            $logfile = $dest;
        }
        if ( !defined $logfile ) {
            confess "logfile not defiend";
        }
        return $logfile;
    }
}

=head2 logf

=cut

sub logf {
    my $msg = shift;
    if ( logdest() eq 'screen' ) {
        say $msg;
    } elsif ( logdest() eq 'file' && defined logfile() ) {
        open my $fh, '>>', logfile();
        print $fh $msg . "\n";
        close $fh;
    } else {
        confess "Do not know where to dolog logdest(): "
            . ( logdest() // 'undef' )
            . " logfile():"
            . ( logfile() // 'undef' );
    }
}

=head2 store_result

Log result

=cut

sub store_result {
    my %result = @_;
    open( my $fh, '>>', $homedir . '/log/ggp-results.txt' );
    local $Data::Dumper::Indent   = 0;
    local $Data::Dumper::Maxdepth = $Data::Dumper::Maxdepth || 2;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Terse    = 1;

    print $fh Dumper( \%result ) . ",\n";
    logf( data_to_gdl( \%result ) );
    close $fh;
}

=head2 extract_variables

Get data return list of variables (?x ..)

=cut

sub extract_variables {
    my $data = shift;
    my @return;
    for my $eval ( flat @$data ) {
        if ( substr( $eval, 0, 1 ) eq '?' ) {
            push( @return, $eval );
        }
    }
    return @return;
}

=head2 hashify

Takes an array read first value and use this value as key in returning hash.

=cut

sub hashify {
    my @in_array = @_;
    confess "\@in_array is undefined" if !@in_array;
    my $return;
    my %rowcount;
    for my $item (@in_array) {

        if ( ref $item eq 'ARRAY' ) {
            if ( ref $item->[0] eq 'ARRAY' ) {
                warn Dumper @in_array;
                confess "Unhandled. Should becalled recursivily";
                my $tmpret = hashify($item);
                my $merge  = HaMerge->new('RETAINMENT_PRECEDENT');
                my $return = merge( $tmpret, $return );

            } else {
                my $key = shift(@$item);
                if ( @$item > 1 ) {
                    if ( none { Compare( $item, $_ ) } @{ $return->{$key} } ) {
                        push( @{ $return->{$key} }, $item );
                    }
                } elsif ( @$item == 1 ) {
                    $rowcount{$key}++;
                    push( @{ $return->{$key} }, $item->[0] );
                } else {
                    warn Dumper $key;
                    warn Dumper $item;
                    confess "Should not be here $key - " . Dumper $item ;
                }
            }
        } else {
            $return->{$item} = '[true]';
        }
    }
    for my $key ( keys %rowcount ) {
        if ( $rowcount{$key} == 1 && !ref $return->{$key}->[0] ) {
            $return->{$key} = $return->{$key}->[0];

            #  warn "hashify".  Dumper $value;
        }
    }
    return $return;
}

=head2 data_to_gdl

Takes a datastructure and return a string packet as gdl/kif with out line break.

=cut

sub data_to_gdl {
    my $data   = shift;
    return '' if !defined $data;
    my $return = _recstringify($data);
    if ( substr( $return, 0, 1 ) ne '(' && ref $data ) {
        $return = '( ' . $return . ' )';
    }
    return $return;
}

sub _recstringify {
    my $data = shift;
    confess 'Input should not be undef' if any { !defined $_ } ($data);

    my $return;
    my $i   = 0;
    my $ref = ref $data;
    if ( $ref eq 'ARRAY' ) {
        $return .= '( ';
        for my $item (@$data) {
            if ( !defined $item ) {
                warn Dumper $data;
                confess "NULL1";
            }
            $return .= _recstringify($item) . ' ';
        }
        $return .= ')';

    } elsif ( $ref eq 'HASH' ) {
        $return .= '( ';
        my ( $key, $value );
        while ( ( $key, $value ) = each %$data ) {
            $return .= $key . ' ';
            if ( !defined $value ) {
                warn Dumper $data;
                confess "NULL2 '".($key//'__UNDEF__')."'";
            }

            $return .= _recstringify($value) . ' ';
        }
        $return .= ')';
    } else {    #scalar
        $return = $data;
    }
    return $return;
}

=head2 split_gdl

Takes text-line and depth level. Default = 1
return an array ref of splitted elements

=cut

sub split_gdl {
    my $textline   = shift;
    my $rlevel     = shift // 1;    # level to keep paranthesis|dynamic check front and back
    my $return     = [];
    my $result     = [];
    my $tmppath    = $result;
    my $level      = 0;
    my $itemno     = -1;
    my @path       = ();
    my $space_flag = 0;
    return if !$textline;
    return if $textline =~ /^\s*\;/;
    $textline =~ /^/gc;

    for my $i ( 1 .. 1000 ) {

        #        $textline=~/\G\s+/gc;

        if ( $textline =~ /\G(\s+)/gc ) {
            $space_flag = 1;
            if ( $level == $rlevel ) {
                $itemno++;

                #                next;
            } elsif ( defined $return->[$itemno] ) {
                $return->[$itemno] .= $1;
            }

        } else {
            $space_flag = 0;
        }
        if ( $textline =~ /\G([^\(\)\s]+)/gc ) {
            $itemno++ if ( $itemno < 0);# && $level == $rlevel && !$space_flag );    # !space_flag stop undef extra
            $return->[$itemno] .= $1;
            next;
        }
        if ( $textline =~ /\G(\()/gc ) {
            if ( $level >= $rlevel ) {
                $itemno++ if ( $level == $rlevel && !$space_flag );               # !space_flag stop undef extra items
                $return->[$itemno] .= $1;
            }
            $level++;
            next;
        }
        if ( $textline =~ /\G(\))/gc ) {
            $level--;    # must be before since currently inside last level
            if ( $level >= $rlevel ) {
                $return->[$itemno] .= $1;
            }
            next;
        }
        last if $textline =~ /\G$/gc;
        $textline =~ /\G(.)/;
        my $unchar = $1;
        confess "\$i Shall not reach 999. Probably unkown char '$unchar'" . $textline if $i == 999;
    }

    return $return;
}

=head2 cartesian

Takes an array of arrays

return an array of arrays of Cartesian products.

=cut

sub cartesian {
    my @C = map { [$_] } @{ shift @_ };

    foreach (@_) {
        my @A = @$_;

        @C = map {
            my $n = $_;
            map { [ $n, @$_ ] } @C
        } @A;
    }

    return @C;
}

1;

=head1 AUTHOR

Slegga

=cut

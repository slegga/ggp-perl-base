package SH::GGP::Tools::Parser;
use Carp;
use Data::Dumper;
use autodie;
use strict;
use warnings;
use Exporter 'import';
use List::MoreUtils qw(any none uniq);
use List::Flatten;
use File::Slurp;
use Storable qw(dclone);
our @EXPORT_OK = qw(parse_gdl_file parse_gdl gdl_to_data readkifraw gdl_pretty);
my $homedir;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";

use SH::GGP::Tools::Utils qw( data_to_gdl logf);

=encoding utf8

=head1 NAME

SH::GGP::Tools::Parser - Rule parser

=head1 SYNOPSIS

 use SH::GGP::Tools::Parser qw (parse_gdl_file gdl_pretty);
 my $world = parse_gdl_file($file, $opts);
 print gdl_pretty($world);

=head1 DESCRIPTION

Contain functions for transform text to a rule data tree.

=cut


BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}


=head1 FUNCTIONS

=head2 parse_gdl_file

Manager function for transform text to rules in array of array.
Read file and process.

=cut

sub parse_gdl_file {
    my $gdlfilepath = shift;
    my $opts        = shift;
    my $text        = read_file("$homedir/Dropbox/data/kif/$gdlfilepath.kif");

    return parse_gdl( $text, $opts );
}

=head2 parse_gdl

Takes a text string and transform to rules  in array of array ref.

=cut

sub parse_gdl {
    my $text     = shift;
    my $opts     = shift;
    my @gdllines = ();
    my @datakif  = ();
    @gdllines = gdl_concat_lines($text);
    @gdllines = gdl_order_lines(@gdllines);
    if ( $opts->{verbose} ) {
        logf( join( "\n", @gdllines ) );
    }
    for my $line (@gdllines) {
        push( @datakif, gdl_to_data($line) );
    }
    my $rules = readkifraw( \@datakif );
    $rules->{analyze} = analyze_rules($rules);
    return $rules;
}

=head2 gdl_concat_lines

Takes gdl return an array of lines with one statement/command on each item

=cut

sub gdl_concat_lines {
    my $text = shift;
    my @return;
    my $par_balance = 0;
    my $longline    = '';

    #make it easier to read
    for my $line ( split( /\n/, $text ) ) {
        $line =~ s/\s*\;.*//;
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*\;/;
        $par_balance += () = $line =~ /\(/g;
        $par_balance -= () = $line =~ /\)/g;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        $longline .= ' ' . $line;

        if ( $par_balance == 0 ) {
            my $level      = 0;
            my $itno       = 0;
            my @splitlines = ();
            for my $char ( split( '', $longline ) ) {
                if ( $char eq '(' ) {
                    $level++;
                    $splitlines[$itno] .= $char;
                } elsif ( $char eq ')' ) {
                    $level--;
                    $splitlines[$itno] .= $char;
                    if ( !$level ) {
                        $itno++;
                    }
                } else {
                    $splitlines[$itno] .= $char;
                }
            }

            push( @return, @splitlines );
            $longline = '';
        }
    }
    return @return;
}

=head2 gdl_order_lines

Order lines for old non oo code.

=cut

sub gdl_order_lines {
    my @lines = @_;
    my $rlines = gdl_order_and_group_lines(@lines);
    return (@{$rlines->{facts}},@{$rlines->{init}},@{$rlines->{head}},@{$rlines->{body}});
}

=head2 gdl_order_and_group_lines

This method, when it is ready, replace gdl_order_lines.

The goal is to do this with less code.
The code will be split into facts(constants), init, head(next), body(main)

=cut

sub gdl_order_and_group_lines {

    #reorder the lines so first come first
    my @lines = @_;
    my @lastlines;# do this later
    my @mostlastlines;# belongs to a later group
    my $return={facts=>[],init=>[],head=>[],body=>[]};
    my $known = {next=>0, does=>0, true=>0, distinct=>0, or=>0, not=>0, goal=>0, legal=>0, terminal=>0, base=>0, input=>0, noop=>0 };
    my $ok;
    my %missing_words = ();
    my $oldnumret     = 10000;

    # get facts
    for my $line (@lines) {
        if ( $line =~ /^;/ ) {
        } elsif ( $line =~ /\bbase\b/ ) {                            #
        } elsif ( $line =~ /\binput\s*\??\w+\s*\(?\s*(\w+)\b/ ) {    #(<= (input ?player (move
            $known->{$1}=0;
        } elsif ( $line =~ /\blegal\s*\??\w+\s*\(?\s*(\w+)\b/ ) {    #(<= (input ?player (move
            $known->{$1}=0;
            push( @mostlastlines, $line );
        } elsif ( $line =~ /\b(?:next|init|goal|terminal)\b/ ) {    #(<= (input ?player (move
            push( @mostlastlines, $line );
        } elsif ( $line =~ /^\s*\(\<\=\s*/ ) {
            push( @lastlines, $line );
        } else {                                                     # the rest should be constants
            ( $known, $ok ) = _getwords( $line, $known );
            push( @{$return->{facts}}, $line );

        }
    }
    @lines = @lastlines;
    @lastlines=();
    #
    #   Add lines with only facts to the facts group
    #
    my $change=1;
    while ($change) {
        $change=0;
        for my $line (@lines) {
            if ($line =~/\((?:next|init)\b/) {
                push( @mostlastlines, $line );
            } else {
            # FIXME ERROR add lines dependant on init words/functions
                ( $known, $ok ) = _getwords( $line, $known );
                if ($ok) {
                    push( @{$return->{facts}}, $line );
                    $change=1;
                } else {
                    push( @lastlines, $line );
                }
            }
        }
        @lines = @lastlines;
        @lastlines = ();
    }

    #
    #   Do head group
    #
    # must handle next first
    
    push (@lines,@lastlines,@mostlastlines);
    @lastlines = ();
    @mostlastlines = ();
    my $tmpknown={};
    # Add missing next and init  words not defined with init
    for my $line (@lines) {
        if ( $line =~ /\bnext\s*\((\w+)\s*/ ) {    #(<= (input ?player (move
            $tmpknown->{$1}=0;
        } elsif ( $line =~ /\binit\b(.+)/ ) {
            my $rest = $1;
            ( $tmpknown, $ok ) = _getwords( $rest, $tmpknown );
            push( @{$return->{init}}, $line );
        } elsif($line =~ /^\s*\(<=\s*\(?\b(\w+)\b/) {
            $known->{$1}++;
        }
    }
    
    @$known{ keys %$tmpknown } = values %$tmpknown;
    
    my @resultpart = ();
    my @nextlines  = ();
    my $loopcounter = 0;
    while (@lines) {
        my $numret = @lines;

        # if looping use discarded lines again to solve loop
        if ( $numret >= $oldnumret ) {
            push( @lines, @mostlastlines );
            @mostlastlines = ();
            $loopcounter++;
            if ($loopcounter>100) {
                logf(join("\n", @lines));
                logf("\nknown\n".join("\n",keys %$known));
                logf("\nMissing words:\n".join("\n", keys %missing_words));
                die"Loop in creating head group";
            }
        }
        $oldnumret = $numret;
        for my $line (@lines) {
            if ( $line =~ /\bnext\b(.+)/ ) {
                my $rest = $1;
                my $tmpmissing;
                ( $known, $ok, $tmpmissing ) = _getwords( $rest, $known );
                if ($ok) {
                    push( @nextlines, $line );
                } else {
                    for my $tmw(@$tmpmissing){
                        $missing_words{$tmw}=1;
                    }
                    unshift( @lastlines, $line );
                }
            } elsif ( $line =~ /\b(?:goal|terminal|legal)\b/ ) {
                push( @mostlastlines, $line );
            } elsif ($line =~ /\b(?:init)\b/ ) {
                #discard init al ready stored
            } elsif (%missing_words) {
                my ($effect) = ( $line =~ /\(\<\=\s*\(?\b([\w\+]+)\b/ );

                my $tmpmissing;
                ( $known, $ok, $tmpmissing ) = _getwords( $line, $known );
                if ($ok) {
                MISSING_WORDS:
                    for my $mw (keys %missing_words ) {
                        for my $kn (_get_knowns($known)) {
                            if ( exists $missing_words{$kn} ) {
                                delete $missing_words{$kn};
                                next MISSING_WORDS;
                            }
                        }
                    }
                    if ( any { $effect eq $_ } keys %missing_words ) {
                        push( @resultpart, $line );
                        delete $missing_words{$effect};

                    } else {    #no missing words

                        push( @nextlines, $line );
                    }
    #                    push( @nextlines, $line );
                } else {
                    for my $tmw(@$tmpmissing) {
                        $missing_words{$tmw}=1;
                    }
                    unshift( @lastlines, $line );
                }
                
                

                # get effect_word
                # elsif (any {effect_word eq $_} @missing_words) {
            } else {
                push(@mostlastlines,$line);
            }
        }
        @lines     = @lastlines;
        @lastlines = ();
    }
    @lines         = @mostlastlines;
    @mostlastlines = ();
    @lastlines = ();
    @resultpart    = @{ _local_order_lines( \@resultpart ) };
    push( @{$return->{head}}, @resultpart, @nextlines );
    @resultpart = ();

    #
    #   Do body group
    #

    logf( Dumper $known);

    # Handle sentences that is dependent on other sentences
    # @lines     = @lastlines;
    $oldnumret = 10000;
    die if (%missing_words);
    while (@lines) {
        my $numret = @lines;
        if ( $numret >= $oldnumret ) {
            logf("$numret >= $oldnumret");
            logf( "return:".Dumper $return);
            logf( "knowns:" . join( "\n", _get_knowns($known) ) );
            logf( "FAIL2:" . join( "\n", @lines ) );
            confess "Looping cant prosess";
        }
        $oldnumret = $numret;
        for my $line (@lines) {
            ( $known, $ok ) = _getwords( $line, $known );
            if ($ok) {
                push( @{$return->{body}}, $line );
            } else {
                push( @lastlines, $line );
            }
        }
        @lines = @lastlines;

        @lastlines = ();

    }
     logf(Dumper $return);
     
    return $return;

}

sub _get_knowns {
    my $known = shift;
    return grep { $known->{$_}==0 } grep { exists $known->{$_} } keys %$known;
}



#
#
# Return ( $return = known functions/words, $ok = ready to put into list, $known = hashref of remaining occurence of functions, $missing_words = list of functions/words that has to be defined before ok);

sub _getwords {
    my $line          = shift;
    my $known         = shift;
    my $missing_words = [];
    my @new           = ( $line =~ /(?:[\(\=\s])\s*([a-z\+][\w\+]*)/g );
    if ( !@new ) {
        logf("No words from line(1) '$line'");
        return ( $known, 1,  );
    }
    shift(@new) if $new[0] =~ /\b(?:next|init|input)\b/;
    my $ok = 1;
    if ( !@new ) {
        logf("No words from line(2) '$line'");
        return ( $known, 1 );
    }

    # handle (<= (legal2 ?player (move ?x1 ?y1 ?x2 ?y2))... where legal2 and move is new
    
    my $offset = 1;
    
    
    if ($line !~ /\(\<\=/) {
        # line is a fact
        for my $i(0 .. $#new) {
            $known->{$new[$i]}=0;
        }
        return $known, 1;
    }
#     if ( $line =~ /\(\<\=\s*\(\b\w+\b\s*(?:\??\w+\b)\s*\(?\w+/ ) {
#         $offset = 2;
#     }
    for my $word ( @new[ $offset .. $#new ] ) {
        if ( none { $_ eq $word } _get_knowns($known) ) {
            $ok = 0;
            push @$missing_words, $word;

            #logf( "Missing $word line: $line");
        }
    }

    # only ok if no more entries
    if ( $ok && defined $known ) {
        for my $word ( @new[ $offset .. $#new ] ) {
            if ( any { $word eq $_ } keys %$known ) {
                if ( $known->{$word} > 0 ) {
                    my $tmp = $offset - 1;
                    if ( $known->{$word} != 1 || none { $word eq $_ } @new[ 0 .. $tmp ] ) {
                        $ok = 0;
                    }
                }
            }
        }
    }

    my $tmp    = $offset - 1;
    if ($ok) {
        for my $i ( 0 .. $tmp ) {
            if ( exists $known->{ $new[$i] } ) {
                if( $known->{ $new[$i] } > 0 ) {
                    $known->{ $new[$i] }--;
                }
            } else {
                $known->{ $new[$i] } = 0;
            }
        }
    }

    return ( $known, $ok, $missing_words );
}

# bygger datastruktur i stedenfor arrays of arrays
sub _getitem {
    my $ar_of_ar_ref = shift;
    my @path         = @_;
    my $return       = $ar_of_ar_ref;
    for my $id (@path) {
        $return = $return->[$id];
    }
    return $return;
}

# _local_order_lines
#
# Order lines with out storing new words
# lines dependant on other lines will come last
#
# Input : list of rules
# output: same list in order

sub _local_order_lines {
    my $rulelist = shift;
    return [] if !@$rulelist;
    return $rulelist if @$rulelist == 1;
    my $return       = [];
    my @effects      = ();
    my @dependensies = ();

    #    warn Dumper $rulelist;
    for my $i ( 0 .. $#{$rulelist} ) {
        my @flat = ( $rulelist->[$i] =~ /[^\?]\b([\w\+]+)\b/g );
        if ( $flat[0] =~ /^(?:next|legal|termainal|init|base|input)$/ ) {
            shift(@flat);
        }
        $effects[$i]      = $flat[0];
        $dependensies[$i] = \@flat[ 1 .. $#flat ];
    }

    $return = $rulelist;
    return $return;
}

=head2 gdl_to_data

Read one line of compressed gdl-inline

=cut

sub gdl_to_data {
    my $textline = shift;
    my $result   = [];
    my $tmppath  = $result;
    my $level    = 0;
    my $itemno   = 0;
    my @path     = ();
    return if !$textline;
    return if $textline =~ /^\s*\;/;
    $textline =~ /^/gc;

    for my $i ( 1 .. 1000 ) {
        $textline =~ /\G\s+/gc;
        if ( $textline =~ /\G\;/gc ) {
            last;
        }
        if ( $textline =~ /\G([\-\.\w\=\<\?\+]+)/gc ) {
            $tmppath->[$itemno] = $1;
            $itemno++;
            next;
        }
        if ( $textline =~ /\G\(/gc ) {
            push( @path, $itemno );
            $tmppath->[$itemno] = [];
            $tmppath = _getitem( $result, @path );
            $itemno = 0;
            $level++;
            next;

            #            push(@path, $itemvalue[0]);
        }
        if ( $textline =~ /\G\)/gc ) {
            $level--;
            $itemno = pop(@path);
            $itemno++;
            $tmppath = _getitem( $result, @path );
            next;
        }
        last if $textline =~ /\G$/gc;
        $textline =~ /\G(.)/;
        my $unchar = $1;
        confess "\$i Shall not reach 999. Probably unkown char '$unchar'" . $textline if $i == 999;
    }
    my $num = @$result;
    if ( $num > 1 ) {
        confess "Many result from line '$textline'";
    } elsif ( $num == 1 ) {
        return $result->[0];
    } else {
        confess "No result from line '$textline'";
    }
}

=head2 readkifraw

Takes a datastructure

Return a 'world' object of rules,roles,constants and init

=cut

sub readkifraw {
    my $kifraw   = shift;
    my @tmpinits = ();
    my $return   = {};
    confess "$kifraw not ARRAY $kifraw" if ref $kifraw ne 'ARRAY';

    # preprocessing
    # Sort/handle mainfunction (role,init,<=)

    for my $i ( 0 .. $#$kifraw ) {
        confess "$kifraw not ARRAY $i " . $kifraw->[$i] if ref $kifraw->[$i] ne 'ARRAY';
        next if !@{ $kifraw->[$i] };
        my $mainf = $kifraw->[$i]->[0];
        if ( !defined $mainf ) {
            confess "Missing main function $i " . Dumper $kifraw->[$i];
        } elsif ( $mainf eq 'role' ) {
            push( @{ $return->{roles} },               $kifraw->[$i]->[1] );
            push( @{ $return->{constants}->{$mainf} }, $kifraw->[$i]->[1] );
            if ( exists $kifraw->[$i]->[2] ) {
                confess( "$mainf To many args. " . Dumper $kifraw->[$i] );
            }
        } elsif ( $mainf eq 'init' ) {
            push( @tmpinits, $kifraw->[$i]->[1] );
            if ( exists $kifraw->[$i]->[2] ) {
                confess( "$mainf To many args. " . Dumper $kifraw->[$i] );
            }
        } elsif ( $mainf eq '<=' ) {
            my $rule_hr = {};
            $rule_hr->{effect}   = $kifraw->[$i]->[1];
            $rule_hr->{criteria} = [];
            for my $j ( 2 .. $#{ $kifraw->[$i] } ) {
                next if !defined $kifraw->[$i]->[$j];
                push( @{ $rule_hr->{criteria} }, $kifraw->[$i]->[$j] );
            }
            push( @{ $return->{rules} }, $rule_hr );
        } elsif ( $mainf eq 'base' ) {
            logf( "Ignore " . data_to_gdl( $kifraw->[$i] ) );
        } elsif ( $mainf eq 'input' ) {
            logf( "Ignore " . data_to_gdl( $kifraw->[$i] ) );
        } elsif ( none { ref $_ } @{ $kifraw->[$i] } ) {    #constant
            my @contant = @{ $kifraw->[$i] };
            $mainf = shift(@contant);
            push( @{ $return->{constants}->{$mainf} }, \@contant );
        } else {
            logf( Dumper $kifraw->[$i] );
            confess("Unknown main function $mainf");
        }
    }

    #process init
    for my $init (@tmpinits) {
        my $num = @$init;
        my $key = shift(@$init);
        if ( !@$init ) {
            $return->{init}->{$key} = '[true]';
        } elsif ( @$init == 1 ) {
            $return->{init}->{$key} = $init->[0];
        } else {
            if ( !exists( $return->{init}->{$key} ) ) {
                $return->{init}->{$key} = [];
            }
            push( @{ $return->{init}->{$key} }, $init );
        }
    }
    return $return;

    # should probably order criteria in best pick way
    # should probably extract dependensies
}

=head2 ooreadkifraw

 This calculate a word in parts of init,facts,head,body

=cut
 
sub ooreadkifraw {
    my $kifraw   = shift;
    my $return= {};
    # FIXME
    # shall return:
    # ->{init}= data
    # ->{facts} = data
    # ->{head} =datarules
    # ->{body} =datarules
    # ...
    return $return;
}

=head2 analyze_rules

Get meta data about rules. Like number of roles, etc.

Return an hash with info.

=cut

sub analyze_rules {
    my $rule = shift;
    confess "$rule is not defined" if !defined $rule;
    confess "$rule is not an hash ref" if ref $rule ne "HASH";
    my $return = {};

    #    warn Dumper $rule;
    $return->{noofroles}  = scalar @{ $rule->{roles} };
    $return->{goalpolicy} = 'unknown';                    # fixed sum, cooperative, partial competing
    $return->{maxgoal}    = 'unknown';                    # fixed sum, cooperative, partial competing
    $return->{firstmoves} = -1;                           # 0 = unknown
    return $return;
}

=head2 gdl_pretty

Return a string of read friendly output of a gdl

=cut

sub gdl_pretty {
    my $gdl      = shift;
    my $return   = '';
    my $level    = 0;
    my $textline = $gdl;
    for my $i ( 1 .. 1000 ) {
        if ( $level == 0 ) {
            $return .= "\n";
        }
        if ( $textline =~ /\G([^\(\)]+)/gc ) {
            $return .= $1;
            next;
        }
        if ( $textline =~ /\G(\()/gc ) {
            $return .= $1;
            $level++;
            next;

            #            push(@path, $itemvalue[0]);
        }
        if ( $textline =~ /\G(\))/gc ) {
            $return .= $1;
            $level--;
            next;
        }
        last if $textline =~ /\G$/gc;
        $textline =~ /\G(.)/;
        my $unchar = $1;
        confess "\$i Shall not reach 999. Probably unkown char '$unchar'" . $textline if $i == 999;
    }
    return $return;
}

=head1 AUTHOR

Slegga

=cut

1

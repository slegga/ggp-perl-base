package GGP::Tools::RuleOptimizer;
use Carp;
use Data::Dumper;
use autodie;
use strict;
use warnings;
use Exporter 'import';
use List::MoreUtils qw(any none uniq);
use List::Flatten;
use File::Slurp;
use Moo;
use Storable qw(dclone);
our @EXPORT_OK = qw(parse_gdl_file parse_gdl gdl_to_data readkifraw gdl_pretty);
my $homedir;
use Cwd 'abs_path';
BEGIN {
    $homedir = abs_path($0);
    $homedir =~s|/[^/\\]+/[^/\\]+$||;
}
use lib "$homedir/lib";

use GGP::Tools::Utils qw( data_to_gdl logf hashify);

=encoding utf8

=head1 NAME

GGP::Tools::RuleOtimizer - Rule optimizer

=head1 SYNOPSIS

 use GGP::Tools::Parser qw (parse_gdl_file gdl_pretty);
 use GGP::Tools::RuleOptimizer;
 my $world = parse_gdl_file($file, $opts);
 my $world = GGP::Tools::RuleOptimizer->optimize_rules($world);
 print gdl_pretty($world);

=head1 DESCRIPTION

Transform a rule data tree to a optimized rule tree.
The output will be on internal gdl format.
Original critera value is always set by the 'set' commando.
All facts are precalculated if several tables with facts is included, and
indexed.


=cut


=head1 FUNCTIONS


=head2 optimize_rules

Takes rules return optimized rules.
Leave rules with 0 or 1 table of facts alone.
(optional set calculate index for tables accessed several times.)
Rules with two or more fact tables are precalculated. If new table is
lesser than 20 row the precalcfacts are placed first else a other table
is placed first and an index i calculated for the precalcfacts table.
and is changed with index_and.

=cut

sub optimize_rules {
    my $text     = shift;
    my $opts     = shift;
    my @gdllines = ();
    my @datakif  = ();
    my $rules;
    @gdllines = gdl_concat_lines($text);
    my $gdlrule_hr = gdl_order_and_group_lines(@gdllines);
    if ( $opts->{verbose} ) {
        logf( join( "\n", $gdlrule_hr ) );
    }
    for my $part (qw(init facts next body terminal legal goal)) {
        my @tmprules;
        for my $line ( @{ $gdlrule_hr->{$part} } ) {
            push( @tmprules, gdl_to_data($line) );
        }
        $rules->{$part} = readkifraw( \@tmprules );
    }

    #    my $rules = readkifraw( \@datakif );
    #    warn Dumper $rules;
    $rules->{analyze} = analyze_rules($rules);
    return $rules;
}


=head2 gdl_order_and_group_lines

This method, when it is ready, replace gdl_order_lines.

The goal is to do this with less code.
The code will be split into facts(constants), init, next, body(main)

Return an hash ref.

=cut

sub gdl_order_and_group_lines {

    #reorder the lines so first come first
    my @lines = @_;
    my @lastlines;        # do this later
    my @mostlastlines;    # belongs to a later group
    my $return = { facts => [], init => [], next => [], body => [], terminal=>[], legal=>[]
      , goal=>[] };
    my $known = {
        next     => 0,
        does     => 0,
        true     => 0,
        distinct => 0,
        or       => 0,
        not      => 0,
        goal     => 0,
        legal    => 0,
        terminal => 0,
        base     => 0,
        input    => 0,
        noop     => 0
    };
    my $ok;
    my %missing_words = ();
    my $oldnumret     = 10000;

    # get facts
    for my $line (@lines) {
        if ( $line =~ /^;/ ) {
        } elsif ( $line =~ /\bbase\b/ ) {                            #
        } elsif ( $line =~ /\binput\s*\??\w+\s*\(?\s*(\w+)\b/ ) {    #(<= (input ?player (move
            $known->{$1} = 0;
        } elsif ( $line =~ /\blegal\s*\??\w+\s*\(?\s*(\w+)\b/ ) {    #(<= (input ?player (move
            $known->{$1} = 0;
            push( @mostlastlines, $line );
        } elsif ( $line =~ /\b(?:next|init|goal|terminal)\b/ ) {     #(<= (input ?player (move
            push( @mostlastlines, $line );
        } elsif ( $line =~ /^\s*\(\<\=\s*/ ) {
            push( @lastlines, $line );
        } else {                                                     # the rest should be constants
            ( $known, $ok ) = _getwords( $line, $known );
            push( @{ $return->{facts} }, $line );

        }
    }
    @lines     = @lastlines;
    @lastlines = ();
    #
    #   Add lines with only facts to the facts group
    #
    my $change = 1;
    while ($change) {
        $change = 0;
        for my $line (@lines) {
            if ( $line =~ /\(\s*(?:next|init|legal)\b/ ) {
                push( @mostlastlines, $line );
            } elsif ( $line =~ /\bdoes\b/ ) {
                push( @mostlastlines, $line );
            } else {

                # FIXME ERROR add lines dependant on init words/functions
                ( $known, $ok ) = _getwords( $line, $known );
                if ($ok) {
                    push( @{ $return->{facts} }, $line );
                    $change = 1;
                } else {
                    push( @lastlines, $line );
                }
            }
        }
        @lines     = @lastlines;
        @lastlines = ();
    }

    #
    #   Do next group
    #
    # must handle next first

    push( @lines, @lastlines, @mostlastlines );
    @lastlines     = ();
    @mostlastlines = ();
    my $tmpknown = {};

    # Add missing next and init  words not defined with init
    for my $line (@lines) {
        if ( $line =~ /\bnext\s*\((\w+)\s*/ ) {    #(<= (input ?player (move
            $tmpknown->{$1} = 0;
        } elsif ( $line =~ /\binit\b(.+)/ ) {
            my $rest = $1;
            ( $tmpknown, $ok ) = _getwords( $rest, $tmpknown );
            push( @{ $return->{init} }, $line );
        } elsif ( $line =~ /^\s*\(<=\s*\(?\b(\w+)\b/ ) {
            $known->{$1}++;
        }
    }

    @$known{ keys %$tmpknown } = values %$tmpknown;

    my @resultpart  = ();
    my @nextlines   = ();
    my @lastnextlines =();
    my @dependentcies=();
    my $loopcounter = 0;

    for my $line (@lines) {
        if ( $line =~ /\bnext\b(.+)/ ) {
            ( $known, $ok ) = _getwords( $line, $known );
            push( @lastnextlines, $line );
        } elsif ( $line =~ /\b(?:does)\b/ ) {
          my $tmpmissing;
          my ($firstword)= ($line=~/([\w\+]+)/);
          confess("Illegal next: ".$line) if ($firstword eq 'next');
          # ( $known, $ok, $tmpmissing ) = _getwords( $line, $known );
          unshift( @nextlines, $line );
          push(@dependentcies,$firstword);
        } elsif ( $line =~ /\b(?:terminal)\b/ ) {
            push( @{$return->{terminal}}, $line );
        } elsif ( $line =~ /\b(?:legal)\b/ ) {
            push( @{$return->{legal}}, $line );
        } elsif ( $line =~ /\b(?:goal)\b/ ) {
            push( @{$return->{goal}}, $line );
        } elsif ( $line =~ /\b(?:init)\b/ ) {
        } else {
            push( @mostlastlines, $line );
        }
    }
    @lines     = ();
    @lastlines = ();
    my @newdepentancies = ();
    while (@dependentcies) {
      for my $depword(@dependentcies) {
        for my $i (reverse 0 .. $#mostlastlines) {
            if ($mostlastlines[$i] =~ /\b$depword\b/) {
              my ($firstword)= ($mostlastlines[$i]=~/([\w\+]+)/);
              push(@nextlines,$mostlastlines[$i]);
              splice(@mostlastlines, $i,1);

              #TODO
              #add entry in @newdepentancies
              #++ test dots and boxes
              push(@newdepentancies, $firstword);
              # ...
            }
        }
      }
      @dependentcies=@newdepentancies;
      @newdepentancies=();
    }
    push(@mostlastlines, @lastlines);
    push(@nextlines, @lastnextlines);
    @lines         = @mostlastlines;
    @mostlastlines = ();
    @lastlines     = ();
    @resultpart    = @{ _local_order_lines( \@resultpart ) };
    push( @{ $return->{next} }, @resultpart, @nextlines );
    @resultpart = ();

    #
    #   Do body group
    #

    # Handle sentences that is dependent on other sentences
    # @lines     = @lastlines;
    $oldnumret = 10000;
    die if (%missing_words);
    while (@lines) {
        my $numret = @lines;
        if ( $numret >= $oldnumret ) {
            logf("$numret >= $oldnumret");
            logf( "return:" . Dumper $return);
            logf( "knowns:" . join( "\n", sort(_get_knowns($known)) ) );
            logf( "FAIL2:" . join( "\n", @lines ) );
            confess "Looping cant prosess";
        }
        $oldnumret = $numret;
        for my $line (@lines) {
            ( $known, $ok ) = _getwords( $line, $known );
            if ($ok) {
                push( @{ $return->{body} }, $line );
            } else {
                push( @lastlines, $line );
            }
        }
        @lines = @lastlines;

        @lastlines = ();

    }

    return $return;

}

sub _get_knowns {
    my $known = shift;
    return grep { $known->{$_} == 0 } grep { exists $known->{$_} } keys %$known;
}

#
#
# Return ( $return = known functions/words, $ok = ready to put into list, $known = hashref of remaining occurence of functions, $missing_words = list of functions/words that has to be defined before ok);

sub _getwords {
    my $line          = shift;
    my $known         = shift;
    my $missing_words = [];
    my $ok            = 1;
    my $offset        = 1;
    my @new           = ( $line =~ /(?:[\(\=\s])\s*([a-z\+][\w\+]*)/g );
    if ( !@new ) {
        logf("No words from line(2) '$line'");
        return ( $known, 1 );
    }

    my $command = shift(@new) if $new[0] =~ /\b(?:next|init|input)\b/;
    if ( defined $command && $command eq 'next' ) {
        my $effect = $line;
        if ( $line =~ /\s*\(\s*\<\=\s*\(next\s*\(?([^\)]+)/ ) {
            $effect = $1;
            my @new = ( $effect =~ /(?:[\(\=\s])\s*([a-z\+][\w\+]*)/g );
            for my $i ( 0 .. $#new ) {
                $known->{ $new[$i] } = 0;
            }
        } else {
            warn $line;
            confess "Cant handle";
        }
        return $known, 1;

    } else {

        # handle (<= (legal2 ?player (move ?x1 ?y1 ?x2 ?y2))... where legal2 and move is new

        my $offset = 1;

        if ( $line !~ /\(\<\=/ ) {

            # line is a fact
            for my $i ( 0 .. $#new ) {
                $known->{ $new[$i] } = 0;
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

    my $tmp = $offset - 1;
    if ($ok) {
        for my $i ( 0 .. $tmp ) {
            if ( exists $known->{ $new[$i] } ) {
                if ( $known->{ $new[$i] } > 0 ) {
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


=head2 readkifraw

Takes a datastructure

Return a 'world' object of facts, init, next, body

=cut

sub readkifraw {
    my $kifraw   = shift;
    my @tmpinits = ();
    my $return;
    confess "$kifraw not ARRAY $kifraw" if ref $kifraw ne 'ARRAY';
    my $facts = {};

    # preprocessing
    # Sort/handle mainfunction (role,init,<=)

    for my $i ( 0 .. $#$kifraw ) {
        confess "$kifraw not ARRAY $i " . $kifraw->[$i] if ref $kifraw->[$i] ne 'ARRAY';
        next if !@{ $kifraw->[$i] };
        my $mainf = $kifraw->[$i]->[0];
        if ( !defined $mainf ) {
            confess "Missing main function $i " . Dumper $kifraw->[$i];
        } elsif ( $mainf eq 'init' ) {
            push( @tmpinits, $kifraw->[$i]->[1] );
            if ( exists $kifraw->[$i]->[2] ) {
                confess( "$mainf To many args. " . Dumper $kifraw->[$i] );
            }
        } elsif ( $mainf eq '<=' ) {
            my $rule_hr     = {};
            my @tmpcriteria = ();
            $rule_hr->{effect}   = $kifraw->[$i]->[1];
            $rule_hr->{criteria} = [];
            for my $j ( 2 .. $#{ $kifraw->[$i] } ) {
                next if !defined $kifraw->[$i]->[$j];
                push( @tmpcriteria, $kifraw->[$i]->[$j] );
            }

            # put distinct at last so variables are populated
            my @dist = ();
            for my $crit (@tmpcriteria) {
                if ( ref $crit ) {
                    if ( $crit->[0] ne 'distinct' ) {
                        push( @{ $rule_hr->{criteria} }, $crit );
                    } else {
                        push( @dist, $crit );
                    }
                } else {
                    push( @{ $rule_hr->{criteria} }, $crit );
                }
            }
            push( @{ $rule_hr->{criteria} }, @dist );
            push( @$return,                  $rule_hr );

            #         } elsif ( $mainf eq 'base' ) {
            #             logf( "Ignore " . data_to_gdl( $kifraw->[$i] ) );
            #         } elsif ( $mainf eq 'input' ) {
            #             logf( "Ignore " . data_to_gdl( $kifraw->[$i] ) );
        } elsif (any{$mainf eq $_}('legal','next','goal','terminal')){
          #Handles facts inform of legal, next
          my $rule_hr ={};
            $rule_hr->{effect} = $kifraw->[$i];
            $rule_hr->{criteria} = [];
            push( @$return,                  $rule_hr );
            # if ( exists $kifraw->[$i]->[2] ) {
            #     confess( "$mainf To many args. " . Dumper $kifraw->[$i] );
            # }
        } elsif (
            none {
                ref $_;
            }
            @{ $kifraw->[$i] }
            )
        {    #fact
            my @contant = @{ $kifraw->[$i] };
            $mainf = shift(@contant);
            if ( @contant == 1 ) {
                push( @{ $facts->{$mainf} }, $contant[0] );
            } else {
                push( @{ $facts->{$mainf} }, \@contant );
            }
        } else {
            logf( Dumper $kifraw->[$i] );
            confess("Unknown main function $mainf");
        }
    }

    # Put distinct to the end. So there is data to distinct

    # Expnad facts
    if (%$facts) {
        if ( defined $return ) {
            my $statem = GGP::Tools::StateMachine->new();
            $return = $statem->process_part( $return, $facts, 'nil', 'nil' );    #expand facts

            #            confess "Could not handle rulefiles. Not implemented yet";

            # Example rules that not work is hex, 2pffa.
            # Split statemachine into statemachine as top and GDLHandler as botton object.
            # GDLHandler will be GSL spesific and statemachine a manager/ruler class
            # Then make a process method in statemachine to be called to ground the static rules.
        } else {
            $return = $facts;
        }
    }

    #process init
    for my $init (@tmpinits) {
        my $num = @$init;
        my $key = shift(@$init);
        if ( !@$init ) {
            $return->{$key} = '[true]';
        } elsif ( @$init == 1 ) {
            $return->{$key} = $init->[0];
        } else {
            if ( !exists( $return->{$key} ) ) {
                $return->{$key} = [];
            }
            push( @{ $return->{$key} }, $init );
        }
    }
    return $return;

    # should probably order criteria in best pick way
    # should probably extract dependensies
}



=head1 AUTHOR

Slegga

=cut

1
__END__
      6  HASH(0x9c09658)
         'criteria' => ARRAY(0x9c09678)
            0  ARRAY(0x9c04ae0)
               0  'true'
               1  ARRAY(0x9c05210)
                  0  'cell'
                  1  '?x1'
                  2  '?y1'
                  3  '?player'
            1  ARRAY(0x9c052b0)
               0  'succ'
               1  '?x1'
               2  '?x2'
            2  ARRAY(0x9c052e0)
               0  'succ'
               1  '?x2'
               2  '?x3'
            3  ARRAY(0x9c053a0)
               0  'succ'
               1  '?x3'
               2  '?x4'
            4  ARRAY(0x9c053f0)
               0  'succ'
               1  '?y1'
               2  '?y2'
            5  ARRAY(0x9c05440)
               0  'succ'
               1  '?y2'
               2  '?y3'
            6  ARRAY(0x9c05490)
               0  'succ'
               1  '?y3'
               2  '?y4'
            7  ARRAY(0x9c054e0)
               0  'true'
               1  ARRAY(0x9c05280)
                  0  'cell'
                  1  '?x2'
                  2  '?y2'
                  3  '?player'
            8  ARRAY(0x9c05530)
               0  'true'
               1  ARRAY(0x9c05510)
                  0  'cell'
                  1  '?x3'
                  2  '?y3'
                  3  '?player'
            9  ARRAY(0x9c05550)
               0  'true'
               1  ARRAY(0x9c05330)
                  0  'cell'
                  1  '?x4'
                  2  '?y4'
                  3  '?player'
         'effect' => ARRAY(0x9c05140)
            0  'line'
            1  '?player'

will be:
      6  HASH(0x9c09658)
         'criteria' => ARRAY(0x9c09678)
            0  ARRAY(0x9c04ae0)
               0  'true'
               1  ARRAY(0x9c05210)
                  0  'cell'
                  1  '?x1'
                  2  '?y1'
                  3  '?player'
            1  ARRAY(0x9c052b0)
               0  'factsconcat'
               1  '?x1'
               2  '?x2'
               2  '?x3'
               2  '?x4'
               1  '?y1'
               2  '?y2'
               2  '?y3'
               2  '?y4'
            7  ARRAY(0x9c054e0)
               0  'true-lookup'
               1  ARRAY(0x9c05280)
                  0  'cell'
                  1  '?x2'
                  2  '?y2'
                  3  '?player'
            8  ARRAY(0x9c05530)
               0  'true-lookup'
               1  ARRAY(0x9c05510)
                  0  'cell'
                  1  '?x3'
                  2  '?y3'
                  3  '?player'
            9  ARRAY(0x9c05550)
               0  'true-lookup'
               1  ARRAY(0x9c05330)
                  0  'cell'
                  1  '?x4'
                  2  '?y4'
                  3  '?player'
         'effect' => ARRAY(0x9c05140)
            0  'line'
            1  '?player'

package GGP::Tools::RuleOptimizer;
use Carp;
use Data::Dumper;
use autodie;
use strict;
use warnings;
use Exporter 'import';
use List::MoreUtils qw(any none uniq);
use List::Flatten;
use Storable qw(dclone);
my $homedir;
our @EXPORT_OK = qw(optimize_rules);

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
 use GGP::Tools::Parser qw(gdl_pretty parse_gdl_file);
 use GGP::Tools::RuleOptimizer qw (optimize_rules);
 my $world = parse_gdl_file('connectFour');
 my $world = GGP::Tools::RuleOptimizer::optimize_rules($world);
 print gdl_pretty($world);

=head1 DESCRIPTION

Transform a rule data tree to a optimized rule tree.
The output will be on internal gdl format.
Original critera value is always set by the 'set' commando.
All facts are precalculated if several tables with facts is included, and
indexed.


=head1 Testing

perl -Ilib t/RuleOptimizer.t

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
    my $world   = shift;
    my $return;
    for my $rule( @{$world->{body}}) {
      my @factitem=();
      my @varitem=();

      my $newrule={effect=>$rule->{effect}};
      for my $item(@{$rule->{criteria}}) {

        if (any {$item->[0] eq $_} keys %{$world->{facts}} ) {
          push @factitem, $item;
        } else {
          push @varitem, $item;

        }
      }
      if (@factitem>1) {
        push(@{$newrule->{criteria}}, shift(@varitem));
        # $newrule->{fact}->{values} =[['1','2'], ['3','4']];
        # @factrules
            #return @tmpreturn;
        my $rule = GGP::Tools::RuleLine->new(facts=>\@factitem);
        $newrule->{fact} = $rule->get_facts();
    
        push(@{$newrule->{criteria}}, @varitem);
        printf "must concat facts  %s\n", data_to_gdl($newrule);
        push @{$return->{body}}, $newrule; #must change

      } else {
        printf "rule ok           %s\n",data_to_gdl($rule);
        push @{$return->{body}}, $rule;
      }
    }
    return $return;
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

#!/usr/bin/env perl

# perl -Ilib t\RuleOptimizer.t

use GGP::Tools::Parser qw(gdl_pretty parse_gdl_file);
use GGP::Tools::RuleOptimizer qw (optimize_rules);
my $world = parse_gdl_file('connectFour',  { server => 1 });
$world = GGP::Tools::RuleOptimizer::optimize_rules($world);
# print gdl_pretty($world);

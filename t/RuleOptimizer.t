#!/usr/bin/env perl

# perl -Ilib t\RuleOptimizer.t
use Test::More;
use GGP::Tools::Parser qw(gdl_pretty parse_gdl_file);
use GGP::Tools::RuleOptimizer qw (optimize_rules);
my $world = parse_gdl_file('connectFour',  { server => 1 });
$world = GGP::Tools::RuleOptimizer::optimize_rules($world);
is(ref $world->{body},'ARRAY');
# print gdl_pretty($world);
done_testing;

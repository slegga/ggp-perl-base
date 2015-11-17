#!/usr/bin/env perl

# perl -Ilib t/RuleOptimizer.t
use Test::More;
use GGP::Tools::Parser qw(gdl_pretty parse_gdl_file);
use GGP::Tools::RuleOptimizer qw (optimize_rules);
my $world = parse_gdl_file('connectFour',  { server => 1 });
$world = GGP::Tools::RuleOptimizer::optimize_rules($world);
is(ref $world->{body},'ARRAY');
my $world = parse_gdl_file('tictactoe0',  { server => 1 });
my $world2 = GGP::Tools::RuleOptimizer::optimize_rules($world,{verbose=>1});
is_deeply($world,$world2,"Check that nothing is changed if nothing has to change.");
# print gdl_pretty($world);
done_testing;

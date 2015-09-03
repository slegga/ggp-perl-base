#!/usr/bin/env perl
use strict qw(vars);
use Test::More;
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use feature 'say';
use File::Slurp;
use Storable qw(dclone);
#use Test::More;   # instead of tests => 32
my $homedir;
my $gdescfile = 'tictactoe0.kif';
my @movehist;
use Cwd 'abs_path';
BEGIN {
    $homedir = abs_path($0);
    if ($^O eq 'MSWin32') {
        $homedir =~s|\[^\]+\[^\]+$||;
    } else {
        $homedir =~s|/[^/]+/[^/]+$||;
    }
}
use lib "$homedir/lib";
use SH::OOGGP::Tools::StateMachine;
use SH::OOGGP::Tools::Parser qw(parse_gdl);
use SH::OOGGP::Agents::Guided;
use SH::GGP::Tools::Utils qw (split_gdl hashify);
use SH::OOGGP::Tools::Match;
my $textrules= read_file("$homedir/share/kif/ticTacToe.kif");
#my $textrules= '(noop ( mark 3 1 ) )';
#my $textrules= '( START Base.ticTacToe.1424422175994 xplayer (( role xplayer ) ( role oplayer ) ( index 1 ) ( index 2 ) ( index 3 ) ( <= ( base ( cell ?x ?y b ) ) ( index ?x ) ( index ?y ) ) ( <= ( base ( cell ?x ?y x ) ) ( index ?x ) ( index ?y ) ) ( <= ( base ( cell ?x ?y o ) ) ( index ?x ) ( index ?y ) ) ( <= ( base ( control ?p ) ) ( role ?p ) ) ( <= ( input ?p ( mark ?x ?y ) ) ( index ?x ) ( index ?y ) ( role ?p ) ) ( <= ( input ?p noop ) ( role ?p ) ) ( init ( cell 1 1 b ) ) ( init ( cell 1 2 b ) ) ( init ( cell 1 3 b ) ) ( init ( cell 2 1 b ) ) ( init ( cell 2 2 b ) ) ( init ( cell 2 3 b ) ) ( init ( cell 3 1 b ) ) ( init ( cell 3 2 b ) ) ( init ( cell 3 3 b ) ) ( init ( control xplayer ) ) ( <= ( next ( cell ?m ?n x ) ) ( does xplayer ( mark ?m ?n ) ) ( true ( cell ?m ?n b ) ) ) ( <= ( next ( cell ?m ?n o ) ) ( does oplayer ( mark ?m ?n ) ) ( true ( cell ?m ?n b ) ) ) ( <= ( next ( cell ?m ?n ?w ) ) ( true ( cell ?m ?n ?w ) ) ( distinct ?w b ) ) ( <= ( next ( cell ?m ?n b ) ) ( does ?w ( mark ?j ?k ) ) ( true ( cell ?m ?n b ) ) ( or ( distinct ?m ?j ) ( distinct ?n ?k ) ) ) ( <= ( next ( control xplayer ) ) ( true ( control oplayer ) ) ) ( <= ( next ( control oplayer ) ) ( true ( control xplayer ) ) ) ( <= ( row ?m ?x ) ( true ( cell ?m 1 ?x ) ) ( true ( cell ?m 2 ?x ) ) ( true ( cell ?m 3 ?x ) ) ) ( <= ( column ?n ?x ) ( true ( cell 1 ?n ?x ) ) ( true ( cell 2 ?n ?x ) ) ( true ( cell 3 ?n ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 1 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 3 ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 3 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 1 ?x ) ) ) ( <= ( line ?x ) ( row ?m ?x ) ) ( <= ( line ?x ) ( column ?m ?x ) ) ( <= ( line ?x ) ( diagonal ?x ) ) ( <= open ( true ( cell ?m ?n b ) ) ) ( <= ( legal ?w ( mark ?x ?y ) ) ( true ( cell ?x ?y b ) ) ( true ( control ?w ) ) ) ( <= ( legal xplayer noop ) ( true ( control oplayer ) ) ) ( <= ( legal oplayer noop ) ( true ( control xplayer ) ) ) ( <= ( goal xplayer 100 ) ( line x ) ) ( <= ( goal xplayer 50 ) ( not ( line x ) ) ( not ( line o ) ) ( not open ) ) ( <= ( goal xplayer 0 ) ( line o ) ) ( <= ( goal oplayer 100 ) ( line o ) ) ( <= ( goal oplayer 50 ) ( not ( line x ) ) ( not ( line o ) ) ( not open ) ) ( <= ( goal oplayer 0 ) ( line x ) ) ( <= terminal ( line x ) ) ( <= terminal ( line o ) ) ( <= terminal ( not open ) ) ) 30 15)';
#my $textrules= '( INFO )';
print Dumper split_gdl($textrules,1);
my $id='test';
my $world = parse_gdl($textrules,{quiet=>1});
#
# print Dumper $world;
#
my $statem = SH::OOGGP::Tools::StateMachine->new();
my $state = $statem->get_init_state($world);

ok(defined $state,"Init setstate");
ok(!exists $state->{terminal},'not terminal');
$state = $statem->process_move($world, $state, [['mark',1,1],'noop']);
my $arr=split_gdl('( START Base.dotDit.1422367929830 surmounts (( role surmounts ) ))');
# # print Dumper $arr;
ok(@$arr==4, 'split_gdl1');
my $arr2=split_gdl('( PLAY kiosk.ticTacToe-1422777921317 ( mark 1 1 ) noop  )');
# print Dumper $arr2;
ok(@$arr2==4, 'split_gdl2');
# my $arr3=split_gdl('( mark 1 1 ) noop');
# # print Dumper $arr2;
# ok(@$arr3==2, 'split_gdl3');
#
# #(<= legal2 xp (move 1 2 3) (true (control xp))
# #(<= (hasLegalMove ?player) (legal2 ?player ?move))
# ok(exists $state->{hasLegalMove},'Manage variables as arrays'); #
# # print Dumper $state;
# ok(!exists $state->{terminal},'not terminal');
# ok (get_number_of_paricipants({rulefile=>'dotsAndBoxes'}) == 2,'no part');
#



done_testing();   # reached the end safely

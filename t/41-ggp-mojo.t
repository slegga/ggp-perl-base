#use SH::ScriptTest qw(no_plan);#tests=>4;
use Test::More;
use Test::Mojo;
use FindBin;
use lib "$FindBin::Bin/../lib";
print "$FindBin::Bin/../bin/ggp-client.pl";
require "$FindBin::Bin/../bin/ggp-client.pl";
my $t = Test::Mojo->new;
$t->ua->max_redirects(1);
# my $url = 'http://127.0.0.1:3000';
$t->post_ok('/','INFO')->status_is(200)->content_is('( ( name AlphaBetaM ) ( status available ) )');
#my $test=SH::ScriptTest->new(undef,'dev',@ARGV);#projecthome,developmentflag,testsno to execute
#$test->testscript('/home/t527081/git/ggp-perl-base/bin/ggp-client.pl get /INFO','mojoserver.yml');
$t->post_ok('/','( START Base.ticTacToe.1450178356991 xplayer (( role xplayer ) ( role oplayer ) ( index 1 ) ( index 2 ) ( index 3 ) ( <= ( base ( cell ?x ?y b ) ) ( index ?x ) ( index ?y ) ) ( <= ( base ( cell ?x ?y x ) ) ( index ?x ) ( index ?y ) ) ( <= ( base ( cell ?x ?y o ) ) ( index ?x ) ( index ?y ) ) ( <= ( base ( control ?p ) ) ( role ?p ) ) ( <= ( input ?p ( mark ?x ?y ) ) ( index ?x ) ( index ?y ) ( role ?p ) ) ( <= ( input ?p noop ) ( role ?p ) ) ( init ( cell 1 1 b ) ) ( init ( cell 1 2 b ) ) ( init ( cell 1 3 b ) ) ( init ( cell 2 1 b ) ) ( init ( cell 2 2 b ) ) ( init ( cell 2 3 b ) ) ( init ( cell 3 1 b ) ) ( init ( cell 3 2 b ) ) ( init ( cell 3 3 b ) ) ( init ( control xplayer ) ) ( <= ( next ( cell ?m ?n x ) ) ( does xplayer ( mark ?m ?n ) ) ( true ( cell ?m ?n b ) ) ) ( <= ( next ( cell ?m ?n o ) ) ( does oplayer ( mark ?m ?n ) ) ( true ( cell ?m ?n b ) ) ) ( <= ( next ( cell ?m ?n ?w ) ) ( true ( cell ?m ?n ?w ) ) ( distinct ?w b ) ) ( <= ( next ( cell ?m ?n b ) ) ( does ?w ( mark ?j ?k ) ) ( true ( cell ?m ?n b ) ) ( or ( distinct ?m ?j ) ( distinct ?n ?k ) ) ) ( <= ( next ( control xplayer ) ) ( true ( control oplayer ) ) ) ( <= ( next ( control oplayer ) ) ( true ( control xplayer ) ) ) ( <= ( row ?m ?x ) ( true ( cell ?m 1 ?x ) ) ( true ( cell ?m 2 ?x ) ) ( true ( cell ?m 3 ?x ) ) ) ( <= ( column ?n ?x ) ( true ( cell 1 ?n ?x ) ) ( true ( cell 2 ?n ?x ) ) ( true ( cell 3 ?n ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 1 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 3 ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 3 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 1 ?x ) ) ) ( <= ( line ?x ) ( row ?m ?x ) ) ( <= ( line ?x ) ( column ?m ?x ) ) ( <= ( line ?x ) ( diagonal ?x ) ) ( <= open ( true ( cell ?m ?n b ) ) ) ( <= ( legal ?w ( mark ?x ?y ) ) ( true ( cell ?x ?y b ) ) ( true ( control ?w ) ) ) ( <= ( legal xplayer noop ) ( true ( control oplayer ) ) ) ( <= ( legal oplayer noop ) ( true ( control xplayer ) ) ) ( <= ( goal xplayer 100 ) ( line x ) ) ( <= ( goal xplayer 50 ) ( not ( line x ) ) ( not ( line o ) ) ( not open ) ) ( <= ( goal xplayer 0 ) ( line o ) ) ( <= ( goal oplayer 100 ) ( line o ) ) ( <= ( goal oplayer 50 ) ( not ( line x ) ) ( not ( line o ) ) ( not open ) ) ( <= ( goal oplayer 0 ) ( line x ) ) ( <= terminal ( line x ) ) ( <= terminal ( line o ) ) ( <= terminal ( not open ) ) ) 5 5)'
)->status_is(200)->content_is('ready');
$t->post_ok('/','( PLAY Base.ticTacToe.1449224417236 NIL )')->status_is(200)->content_is('( mark 2 2 )');
$t->post_ok('/','( PLAY Base.ticTacToe.1449224417236 (( mark 2 2 ) noop ) )')->status_is(200)->content_is('noop');
$t->post_ok('/','( PLAY Base.ticTacToe.1449224417236 (noop ( mark 1 1 ) ) )')->status_is(200)->content_like(qr/\(\s*mark\s2\s*\d/);
$t->post_ok('/','( STOP Base.ticTacToe.1449224417236 (( mark 2 1 ) noop ) )')->status_is(200)->content_is('done');

done_testing;

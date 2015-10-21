#use SH::ScriptTest qw(no_plan);#tests=>4;
use Test::More;
use Test::Mojo;
use FindBin;
use lib "$FindBin::Bin/../lib";
require "$FindBin::Bin/../bin/ggp-client.pl";
my $t = Test::Mojo->new;
$t->ua->max_redirects(1);
# my $url = 'http://127.0.0.1:3000';
$t->post_ok('/','INFO')->status_is(200)->content_is('( ( name AlphaBetaM ) ( status available ) )');
#my $test=SH::ScriptTest->new(undef,'dev',@ARGV);#projecthome,developmentflag,testsno to execute
#$test->testscript('/home/t527081/git/ggp-perl-base/bin/ggp-client.pl get /INFO','mojoserver.yml');
done_testing;

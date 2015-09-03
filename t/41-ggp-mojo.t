use SH::ScriptTest qw(no_plan);#tests=>4;
# use Test::Mojo;
# BEGIN {    push(@INC,$ENV{HOME}.'/bin');};
#my $t = Test::Mojo->new();
# my $url = 'http://127.0.0.1:3000';
#$t->post_ok($url.'/INFO')->status_is(200);
my $test=SH::ScriptTest->new(undef,'dev',@ARGV);#projecthome,developmentflag,testsno to execute
$test->testscript('/home/t527081/git/ggp-perl-base/bin/ggp-client.pl get /INFO','mojoserver.yml');
done_testing;

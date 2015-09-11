use SH::ScriptTest qw(no_plan);#tests=>4;
my $test=SH::ScriptTest->new(undef,'dev',@ARGV);#projecthome,developmentflag,testsno to execute
#FIXME
#Loop over all agents
use Cwd 'abs_path';
BEGIN {
    $homedir = abs_path($0);
    if ($^O eq 'MSWin32') {
        $homedir =~s|/[^/\\]+/[^/\\]+$||;
    } else {
        $homedir =~s|/[^/]+/[^/]+$||;
    }
}
$test->testscript($homedir.'/bin/ooggp-match.pl');

opendir(my $dh, $homedir.'/lib/GGP/Agents') || die "can't opendir $some_dir: $!";
for my $agent(map { $_ =~ s/\.pm$//;$_} grep {$_ =~/\.pm$/} readdir($dh) ){
    $test->testscript($homedir."/bin/ooggp-match.pl -t1 -a $agent,$agent");
}
$test->testscript($homedir.'/bin/ggp-report.pl');
# $test->testscript($homedir.'/bin/ggp-match.pl');
$test->testscript($homedir.'/bin/ggp-con-ua.pl --help');
$test->testscript($homedir.'/bin/ggp-series.pl --help');
$test->testscript($homedir.'/bin/ggp-series.pl -r 2pffa,ticTacToe -a MaxMaxH,AlphaBeta -t5');
done_testing;

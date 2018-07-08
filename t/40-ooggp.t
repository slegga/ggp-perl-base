
#FIXME
#Loop over all agents
use Mojo::Base -strict;
use Test::More 'no_plan';
use Test::Script;
use Mojo::File 'path';
use Cwd 'abs_path';
push(@INC,'../utillities-perl/lib');
#my $test=SH::ScriptTest->new($homedir,'dev',@ARGV);#projecthome,developmentflag,testsno to execute
my $bin = path('bin');

opendir(my $dh, path("$bin","..",'lib','GGP','Agents')) || die "can't opendir: $!";
for my $agent(map { $_ =~ s/\.pm$//;$_} grep {$_ =~/\.pm$/} readdir($dh) ){
    script_runs($bin->child('ggp-match.pl')->to_string," -t1 -a $agent,$agent","$agent is working");
}
my $script = path('script');
for my $s($script->list->each) {
	script_compiles("$s","$s compiles");
}
for my $s($bin->list->each) {
	script_compiles("$s","$s compiles");
}
script_runs($bin->child('ggp-series.pl')->to_string, '--help',"help runs");
script_runs($bin->child('ggp-series.pl')->to_string, ' -r 2pffa,ticTacToe -a MaxMaxH,AlphaBeta -t5',"ttt mmh runs");
done_testing;

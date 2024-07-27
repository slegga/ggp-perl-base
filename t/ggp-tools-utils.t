use GGP::Tools::Utils;
use Test2::V0;
use Mojo::File 'path';

# Logging
is(GGP::Tools::Utils::logdest('file'), 'file');
is(GGP::Tools::Utils::logfile('/tmp/testfile.log'), '/tmp/testfile.log');
my $logfile = path(GGP::Tools::Utils::logfile());
$logfile->spew('');
GGP::Tools::Utils::logf('text');
is ($logfile->slurp,'text
');

is(GGP::Tools::Utils::extract_variables(['active','playerx','?player']),(0,1));

is( GGP::Tools::Utils::hashify( ['key','value'],['key2','value2'] ), {key=>'value',key2=>'value2'} );
is( GGP::Tools::Utils::data_to_gdl( [['key','value'],{'key2','value2'}] ), "( ( key value ) ( key2 value2 ) )" );
is( GGP::Tools::Utils::split_gdl( '( key value ) ( key2 value2 )'), [ 'key', 'value',undef , 'key2', 'value2' ] );
done_testing;




__END__

(role player)
(light p) (light q)
(<= (legal player (turnOn ?x)) (not (true (on ?x))) (light ?x))
(<= (next (on ?x)) (does player (turnOn ?x)))
(<= (next (on ?x)) (true (on ?x)))
(<= terminal (true (on p)) (true (on q)))
(<= (goal player 100) (true (on p)) (true (on q)))
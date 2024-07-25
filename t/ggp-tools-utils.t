use GGP::Tools::Utils;
use Test2::V0;
use Mojo::File 'path';
#        if ( substr( $eval, 0, 1 ) eq '?' ) {
#sub hashify {
#sub data_to_gdl {
#sub split_gdl {
#sub cartesian {

# Logging
is(GGP::Tools::Utils::logdest('file'), 'file');
is(GGP::Tools::Utils::logfile('/tmp/testfile.log'), '/tmp/testfile.log');
my $logfile = path(GGP::Tools::Utils::logfile());
$logfile->spew('');
GGP::Tools::Utils::logf('text');
is ($logfile->slurp,'text
');

is(GGP::Tools::Utils::extract_variables(['active','playerx','?player']),(0,1));

done_testing;
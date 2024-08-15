use GGP::Tools::Variables;
use Test2::V0;
use Mojo::File 'path';

# sub new($class_name) {
# # sub reset($self) {
# sub get($self) {
# sub table( $self ) {
# sub variable( $self ) {
# sub get_bool($self) {
# Main sub. Shall make a x-product of current table and input table
# sub do_and($self,$input) {
# sub do_or($self, $tables_ar, $effect) {
#         #substract data
# sub distinct($self, $inputs) {


# Logging
my $vars = GGP::Tools::Variables->new();
my $stat_hr = {};
my $criteria = [ undef ];
ok($vars,'dummy');
# $vars->do_and( $self->true( $state_hr, $criteria->[0], $vars ) );
# is($vars, {});
done_testing;




__END__

(role player)
(light p) (light q)
(<= (legal player (turnOn ?x)) (not (true (on ?x))) (light ?x))
(<= (next (on ?x)) (does player (turnOn ?x)))
(<= (next (on ?x)) (true (on ?x)))
(<= terminal (true (on p)) (true (on q)))
(<= (goal player 100) (true (on p)) (true (on q)))
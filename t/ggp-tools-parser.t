use GGP::Tools::Parser;
use Test2::V0;
use Mojo::File 'path';
use Data::Dumper;

# sub parse_gdl {
# sub gdl_concat_lines {
# sub gdl_order_and_group_lines {
# sub gdl_to_data {
# sub readkifraw {
# sub analyze_rules {
# sub gdl_pretty {

my $world = GGP::Tools::Parser::parse_gdl_file('minisimpletest');
is ($world,{
        'legal' => [ {
            'effect' => [ 'legal', 'player', [ 'turnOn', '?x' ] ],
            'criteria' => [
                [ 'light', '?x' ],
                [ 'not', [ 'true', ['on', '?x' ] ] ],
            ]
        } ],
        'body' => undef,
        'terminal' => [ {
            'effect' => 'terminal'  ,
            'criteria' => [
                [ 'true', [ 'on', 'p' ] ],
                [ 'true', [ 'on', 'q' ] ]  ] } ],
        'facts' => {
            'light' => [ 'p', 'q' ],
            'role' => [ 'player' ] },
        'analyze' => {
            'noofroles' => 1,
            'firstmoves' => -1,
            'goalpolicy' => 'unknown',
            'maxgoal' => 'unknown'
          },
        'next' => [ {
            'effect' => [
                'next', [ 'on', '?x' ] ] ,
            'criteria' => [
                [ 'does', 'player', [ 'turnOn', '?x' ] ] ],
            },
            {
            'effect' => [ 'next', [ 'on', '?x' ] ],
            'criteria' => [ [ 'true', [ 'on', '?x' ] ] ]
            }
            ],
       'init' => undef,
       'goal' => [
            { 'effect' => [ 'goal', 'player', '100' ],
              'criteria' => [
                [ 'true', [ 'on', 'p' ] ],
                [ 'true', [ 'on', 'q' ] ] ] }
            ]
        });

my $world2 = GGP::Tools::Parser::parse_gdl('(role player)
(light p)(light q)
(<= (legal player (turnOn ?x)) (light ?x)(not (true (on ?x))) )
(<= (next (on ?x)) (does player (turnOn ?x)))
(<= (next (on ?x)) (true (on ?x)))
(<= terminal (true (on p)) (true (on q)))
(<= (goal player 100) (true (on p)) (true (on q)))
');
is($world, $world2);

done_testing;




__END__

(role player)
(light p) (light q)
(<= (legal player (turnOn ?x)) (not (true (on ?x))) (light ?x))
(<= (next (on ?x)) (does player (turnOn ?x)))
(<= (next (on ?x)) (true (on ?x)))
(<= terminal (true (on p)) (true (on q)))
(<= (goal player 100) (true (on p)) (true (on q)))

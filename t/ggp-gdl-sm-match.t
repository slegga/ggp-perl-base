use Test::More qw(no_plan);
use Storable qw(dclone);
use warnings;
use strict;
my $homedir;
my $gdescfile = 'tictactoe0.kif';
use Cwd 'abs_path';
BEGIN {
    $homedir = abs_path($0);
    $homedir =~s|[^\/\\]+[\/\\][^\/\\]+$||;
}
use lib "$homedir/lib";
use GGP::Tools::StateMachine (); #qw ( process_move);
use GGP::Tools::Parser qw(parse_gdl);
use GGP::Agents::Random; #qw (info start play stop abort);
use GGP::Tools::Utils  qw( hashify logf);
sub test_short_match {
    my $world = shift;
    my $statem = GGP::Tools::StateMachine->new();
    my $state = $statem->get_init_state($world);
    $statem->init_state_analyze( $world, $state );    #modifies $world
    my $id = 'testing';
    my @roles;

    for my $i (0 .. $#{ $world->{facts}->{role} } ) {
       $roles[$i] = {name=>'Random', agent=>GGP::Agents::Random->new()};
       $roles[$i]{agent}->start($id,$world->{facts}->{role}->[$i],$world,5,5,3);
    }
    my $oldmoves = 'nil';
    my $newmoves = [];
    my $test = 1;
    for (0 .. 1) {
       $state = $statem->process_move($world, $state, $oldmoves);
       for my $r(0 .. $#roles) {
          $newmoves->[$r] = $roles[$r]{agent}->play($id,$oldmoves,$state);
       }
       if (exists $state->{'terminal'}) {
         $test = 0;
       }
       $oldmoves = dclone $newmoves;
    }
    ok($test,'Check for fast endings' );
}

opendir(my $dh,"$homedir/share/kif") || die "can't opendir $homedir/share/kif: $!";
my @rulefiles = readdir( $dh );
for my $file(@rulefiles) {
    next if $file !~ /\.kif$/;
    next if $file =~/proptest/;
    $file =~ s/\.kif$//;
    diag "$file";
    my $world = GGP::Tools::Parser::parse_gdl_file($file);
    test_short_match( $world );
}
closedir $dh;

use Test::More qw(no_plan);
use Storable qw(dclone);
use warnings;
use strict;
my $homedir;
my $gdescfile = 'tictactoe0.kif';
BEGIN {
    if ($^O eq 'MSWin32') {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/lib";
use SH::OOGGP::Tools::StateMachine (); #qw ( process_move);
use SH::OOGGP::Tools::Parser qw(parse_gdl);
use SH::OOGGP::Agents::Random; #qw (info start play stop abort);
use SH::GGP::Tools::Utils  qw( hashify extract_variables data_to_gdl logf);
sub test_short_match {
    my $world = shift;
    my $statem = SH::OOGGP::Tools::StateMachine->new();
    my $state = $statem->get_init_state($world);
    $statem->init_state_analyze( $world, $state );    #modifies $world
    my $id = 'testing';
    my @roles;
    
    for my $i (0 .. $#{ $world->{facts}->{role} } ) {
       $roles[$i] = {name=>'Random', agent=>SH::OOGGP::Agents::Random->new()};
       $roles[$i]{agent}->start($id,$world->{facts}->{role}->[$i],$world,5,5,3);
    }
    my $oldmoves = 'nil';
    my $newmoves = [];
    my $test=1;
    for (0.. 1) {
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

opendir(my $dh,"$homedir/Dropbox/data/kif") || die "can't opendir $homedir/Dropbox/data/kif: $!";
my @rulefiles = readdir( $dh );
for my $file(@rulefiles) {
    next if $file !~ /\.kif$/;
    next if $file =~/proptest/;
    $file =~ s/\.kif$//;
    diag "$file";
    my $world = SH::OOGGP::Tools::Parser::parse_gdl_file($file);
    test_short_match( $world );
}
closedir $dh;


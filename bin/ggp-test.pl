#!/usr/bin/env perl
use Data::Dumper;
use Carp;
my $homedir;
use 5.016;
use Cwd 'abs_path';
BEGIN {
    $homedir = abs_path($0);
    if ($^O eq 'MSWin32') {
        $homedir =~s|\[^\]+\[^\]+$||;
    } else {
        $homedir =~s|/[^/]+/[^/]+$||;
    }
}
use lib "$homedir/lib";
use GGP::Agents::Guided;
use GGP::Tools::Parser qw(parse_gdl gdl_to_data readkifraw gdl_pretty);
use GGP::Tools::Utils qw(data_to_gdl split_gdl);
my $agent = GGP::Agents::Guided->new(4,0,7,0,0,0,0,0,0,0);
my $world;
say request_from_server('( INFO )');



 my $data = request_from_server('( START Base.ticTicToe.1418115139790 xplayer (( role xplayer ) ( role oplayer ) ( <= ( base ( cell ?m ?n x ) ) ( index ?m ) ( index ?n ) ) ( <= ( base ( cell ?m ?n o ) ) ( index ?m ) ( index ?n ) ) ( <= ( base ( cell ?m ?n b ) ) ( index ?m ) ( index ?n ) ) ( base ( control white ) ) ( base ( control black ) ) ( base ( step 1 ) ) ( <= ( base ( step ?n ) ) ( succ ?m ?n ) ) ( <= ( input ?p ( mark ?m ?n ) ) ( index ?m ) ( index ?n ) ( role ?p ) ) ( index 1 ) ( index 2 ) ( index 3 ) ( init ( cell 1 1 b ) ) ( init ( cell 1 2 b ) ) ( init ( cell 1 3 b ) ) ( init ( cell 2 1 b ) ) ( init ( cell 2 2 b ) ) ( init ( cell 2 3 b ) ) ( init ( cell 3 1 b ) ) ( init ( cell 3 2 b ) ) ( init ( cell 3 3 b ) ) ( init ( step 1 ) ) ( <= ( next ( cell ?j ?k x ) ) ( true ( cell ?j ?k b ) ) ( does xplayer ( mark ?j ?k ) ) ( does oplayer ( mark ?m ?n ) ) ( or ( distinct ?j ?m ) ( distinct ?k ?n ) ) ) ( <= ( next ( cell ?m ?n o ) ) ( true ( cell ?m ?n b ) ) ( does xplayer ( mark ?j ?k ) ) ( does oplayer ( mark ?m ?n ) ) ( or ( distinct ?j ?m ) ( distinct ?k ?n ) ) ) ( <= ( next ( cell ?m ?n b ) ) ( true ( cell ?m ?n b ) ) ( does xplayer ( mark ?m ?n ) ) ( does oplayer ( mark ?m ?n ) ) ) ( <= ( next ( cell ?p ?q b ) ) ( true ( cell ?p ?q b ) ) ( does xplayer ( mark ?j ?k ) ) ( does oplayer ( mark ?m ?n ) ) ( or ( distinct ?j ?p ) ( distinct ?k ?q ) ) ( or ( distinct ?m ?p ) ( distinct ?n ?q ) ) ) ( <= ( next ( cell ?m ?n ?w ) ) ( true ( cell ?m ?n ?w ) ) ( distinct ?w b ) ) ( <= ( next ( step ?y ) ) ( true ( step ?x ) ) ( succ ?x ?y ) ) ( succ 1 2 ) ( succ 2 3 ) ( succ 3 4 ) ( succ 4 5 ) ( succ 5 6 ) ( succ 6 7 ) ( <= ( row ?m ?x ) ( true ( cell ?m 1 ?x ) ) ( true ( cell ?m 2 ?x ) ) ( true ( cell ?m 3 ?x ) ) ) ( <= ( column ?n ?x ) ( true ( cell 1 ?n ?x ) ) ( true ( cell 2 ?n ?x ) ) ( true ( cell 3 ?n ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 1 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 3 ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 3 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 1 ?x ) ) ) ( <= ( line ?x ) ( row ?m ?x ) ) ( <= ( line ?x ) ( column ?m ?x ) ) ( <= ( line ?x ) ( diagonal ?x ) ) ( <= nolinex ( not ( line x ) ) ) ( <= nolineo ( not ( line o ) ) ) ( <= ( legal xplayer ( mark ?x ?y ) ) ( true ( cell ?x ?y b ) ) ) ( <= ( legal oplayer ( mark ?x ?y ) ) ( true ( cell ?x ?y b ) ) ) ( <= ( goal xplayer 50 ) ( line x ) ( line o ) ) ( <= ( goal xplayer 100 ) ( line x ) nolineo ) ( <= ( goal xplayer 0 ) nolinex ( line o ) ) ( <= ( goal xplayer 50 ) nolinex nolineo ( true ( step 7 ) ) ) ( <= ( goal oplayer 50 ) ( line x ) ( line o ) ) ( <= ( goal oplayer 100 ) nolinex ( line o ) ) ( <= ( goal oplayer 0 ) ( line x ) nolineo ) ( <= ( goal oplayer 50 ) nolinex nolineo ( true ( step 7 ) ) ) ( <= terminal ( true ( step 7 ) ) ) ( <= terminal ( line x ) ) ( <= terminal ( line o ) ) ) 30 15)');
say Dumper gdl_pretty($data);

sub request_from_server {
    my $gdl = shift;
    say $gdl;
    my ( $world, $state, $goals );
    my $request = split_gdl( $gdl );
    # my $request = gdl_to_data($gdl);
    #  print "\n\n$content\n";
    my $gdldata;

        if (uc $request->[0] eq 'INFO') {
        $gdldata = $agent->info();
    } elsif (uc $request->[0] eq 'START') {
                ( $world, $state, $goals ) = ( (), (), () );
        print Dumper $request->[2];
        $request->[3] = substr( $request->[3], 1, length( $request->[3] ) - 2 );
        print Dumper $request->[3];
        $world = parse_gdl( $request->[3], {} );
        $gdldata = $agent->start($request->[1],$request->[2],$world,$request->[4],$request->[5]);

    } elsif (uc $request->[0] eq 'PLAY') {
        $gdldata = $agent->play($request->[1],$request->[2],$world->{state});
    } elsif (uc $request->[0] eq 'ABORT') {
        $gdldata = $agent->abort($request->[1]);
    } elsif (uc $request->[0] eq 'STOP') {
        $gdldata = $agent->stop($request->[1]);
    } else {
        confess "UNKNOWN REQUEST ".$request->[0];
    }
    return data_to_gdl($gdldata);
}

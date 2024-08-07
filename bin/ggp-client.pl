#!/usr/bin/env perl
use Mojolicious::Lite;
use Data::Dumper;
use Carp;
use strict;
use warnings;
use Storable qw(dclone);
my $homedir;

use FindBin;
use lib "$FindBin::Bin/../lib";

use GGP::Tools::StateMachine;
use GGP::Tools::Parser qw(parse_gdl gdl_to_data readkifraw  );
use GGP::Tools::Utils qw (logf logdest logfile data_to_gdl split_gdl hashify);

#use GGP::Agents::Random qw (info start play stop abort);
#use GGP::Agents::CompulsiveDeliberation qw (info start play stop abort);
use GGP::Agents::MaxMax;
use GGP::Agents::AlphaBetaM;
use GGP::Agents::Random;

=encoding utf8

=head1 NAME

ggp-client.pl

=head1 DESCRIPTION

This script is planned to use as player on ggp-sites.

=head2 TEST1

prove -l t/41-ggp-mojo.t 2>&1|bin/htmlremover.pl


=head2 TEST


 MOJO_INACTIVITY_TIMEOUT=180 morbo ggp-client.pl
 MOJO_INACTIVITY_TIMEOUT=180 ggp-client.pl daemon

=head2 TEST2

 # shell 1
 cd ~/git/ggp-base
 ./gradlew server

 # shell 2
 cd ~/git/ggp-base
 ./gradlew player

 # shell 3
 cd ~/git/ggp-perl-base
 MOJO_INACTIVITY_TIMEOUT=180 morbo bin/ggp-client.pl 2>&1|grep -v debug|grep -v INFO


=head2 PLAN

Make another Mojolicious script with ua to explore ggp-clients

=cut

#my $agent = GGP::Agents::Guided->new(4,0,7,0,0,0,0,0,0,0);
#my $agent = GGP::Agents::Random->new();
my $agent = GGP::Agents::AlphaBetaM->new();
my ( $world, $state, $goals );
my $statem;
my @roles;
my $oldout = '';
logdest('file');
my $logfile = "$FindBin::Bin/../log/ggp-client.log";
if ( -f $logfile ) {
    unlink($logfile);
}
logfile($logfile);

#my $state = $world->{init};
# Add new MIME type
sub startup {
    my $c = shift;

    # Add new MIME type
    $c->types->type( txt => 'text/acl; charset=utf-8' );
}


# helper

    any '/:foo' => sub {
    my $c   = shift;
    my $foo = $c->param('foo');
    print $foo;
    $c->render( text => "Hello from $foo." );
    };

any '/' => sub {
    my $c = shift;

    #my $content = $c->param('content');#'content' => '( INFO )',

    #print $c->req->content->asset->{content};
    #my $request = gdl_to_data($c->req->content->asset->{content});
    my $request = split_gdl( $c->req->content->asset->{content} );
    warn Dumper( data_to_gdl($request) );
    print "\n\n" . $c->req->content->asset->{content} . "\n";
    my $gdldata;

    if ( uc $request->[0] eq 'INFO' ) {
        $gdldata = $agent->info();
    } elsif ( uc $request->[0] eq 'START' ) {
#        undef($world);
#        undef($state);
#        undef($goals);
#        undef($statem);
        logf($c->req->content->asset->{content});
        # print Dumper $request->[2];
        $request->[3] = substr( $request->[3], 1, length( $request->[3] ) - 2 );
        print Dumper $request->[3];
        $world = parse_gdl( $request->[3], {} );
        confess "No World!" if !defined $world;
        if ( ref $world ne 'HASH' ) {
            print Dumper $world;
            confess "No hash ref";
        }

        # $world = readkifraw($request->[3]);
        logf( data_to_gdl($world) );
        $statem = GGP::Tools::StateMachine->new($world, \@roles);
        $state = $statem->get_init_state($world);
        $statem->init_state_analyze( $world, $state );    #modifies $world
        $gdldata = $agent->start( $request->[1], $request->[2], $world, $request->[4], $request->[5] );
        logf('State:');
        logf( data_to_gdl($state) );
        #         if (defined $world->{constants}) {
        #             $state = dclone($world->{constants});
        #         }
        #         $state->{Constants} = $world->{constants};
        #         @$state{keys %{$world->{init}}} = values %{$world->{init}};
        #         my $other = query_other($world, $state);
        #         @$state{keys %$other} = values %$other;

    } elsif ( uc $request->[0] eq 'PLAY' ) {
        confess "No World!" if !defined $world;

        #0=command 1=id 2+=player moves
        my $moves = $request->[2];
        print Dumper $moves;
        logf($c->req->content->asset->{content});

        #        shift(@$moves);
        #        shift(@$moves);
        my $moves2;
        if ( lc $request->[2] ne 'nil' ) {
            chomp($moves);
            $moves = split_gdl($moves);

            for my $move (@$moves) {
                push @$moves2, gdl_to_data($move);
            }
            print Dumper $moves2, $state->{legal}, $state->{control};
            $state = $statem->process_move( $world, $state, $moves2 );    #['mark'=>[1,1],'noop']

        } else {
            $moves2 = $moves;
        }

        #play (id,moves,state)
        #warn dumper $state;
        $gdldata = $agent->play( $request->[1], $moves2, $state );

    } elsif ( uc $request->[0] eq 'ABORT' ) {
        $gdldata = $agent->abort( $request->[1] );
    } elsif ( uc $request->[0] eq 'STOP' ) {
        $gdldata = $agent->stop( $request->[1] );
    } else {
        confess "UNKNOWN REQUEST " . $request->[0];
    }
    my $out = data_to_gdl($gdldata);
    if ( $out ne $oldout ) {
        warn $out;
    }
    $oldout = $out;
    $c->render( 'text' => $out, format => 'acl' );
};
app->secrets(['dsahfjsfadfhakjfdsjfj']);
app->start;

=head1 AUTHOR

Slegga

=cut

#!/usr/bin/env perl
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use feature 'say';
use File::Slurp;
use Storable qw(dclone);

=encoding utf8

=head1 NAME

ooggp-match.pl - run a match CLI

=head1 DESCRIPTION

Run one match with given inputs

=cut

# Enable warnings within the Parse::RecDescent module.
my $gdescfile = 'tictactoe0';
my @movehist;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../utilities-perl/lib";
use GGP::Tools::Match qw ( run_match list_rules list_agents);
use SH::ScriptX;
use Mojo::Base 'SH::ScriptX';
use GGP::Tools::Parser qw ( parse_gdl_file);
use GGP::Tools::RuleOptimizer qw (optimize_rules);
use GGP::Tools::StateMachine;# qw ( get_init_state  init_state_analyze);
use GGP::Tools::Utils qw (logdest logfile);
use SH::PrettyPrint;
#  qw(rs_convert_from_hashes rs_pretty_format_table rs_aggregate);
#use SH::PrettyPrint 'print_arrayofarrays';
#use Data::printer;
my $homedir = $FindBin::Bin."/..";
option 'info!', 'Info of rules and agents' ;
option 'rulefile=s', 'Name og rule file', { 'default' => $gdescfile } ;
option 'agents=s',     'A list of agents comma separated (guidedf,guidedl)' ;
option 'duplex!',      'Run a match where each particitant try each role' ;
option 'quiet!',       'Print only result' ;
option 'verbose!',     'Print log info' ;
option 'watch=s',      'Comma separated list of state keys to watch' ;
option 'watchrule=s',    'Not implemented yet. Show expanded rule' ;
option 'server',       'Print data to file' ;
option 'iterations=i', 'Max states calculated' ;
option 'timed=i',        'Count how many games in n minutes.', ;

sub main {
    my $self = shift;
    my $opts = {};
    for my $ar(qw/info rulefile agents duplex quiet verbose watch watchrule server iterations timed/) {
        $opts->{$ar} = $self->$ar;
    }

    if ( $self->info ) {
        print "\nrules:\n " . join( "\n ", list_rules() );
        print "\n\n";
        print "agents:\n " . join( "\n ", list_agents() );
        print "\n\n";
        if ( $opts->{verbose} ) {
            my @allrules = list_rules();
            my @output   = ();
            for my $rule (@allrules) {
                my $world = parse_gdl_file( $rule, { server => 1 } );
                my $state = $->get_init_state($world);
                init_state_analyze( $world, $state );    #modifies $world
                my $tmp = $world->{analyze};

                #print "$rule: ".Dumper $world->{analyze};
                $tmp->{rule} = $rule;
                push( @output, $tmp );

            }
    #        my $rs = rs_convert_from_hashes( \@output,
    #            [ 'rule', 'noofroles', 'firstmoves', 'goalheuristic' ] );
    #        print rs_pretty_format_table($rs);
            SH::PrettyPrint::print_hashes \@output;

        }
    } elsif ( $self->timed ) {
        logdest('file');
        my $logfile = $homedir . '/log/ggp-match.log';
        if ( -f $logfile ) {
            unlink($logfile);
        }
        logfile($logfile);

        # Run the same game again and again until time is up.
        # Count number of games.
        # For use in speed testing
        my @agents = ();
        my %result;
        if ( $opts->{agents} ) {
            @agents = $opts->{agents} ? split( /\,/, $opts->{agents} ) : ();
        }
        my $world = parse_gdl_file( $opts->{rulefile}, $opts );
        $world = GGP::Tools::RuleOptimizer::optimize_rules($world);

        my $statem = GGP::Tools::StateMachine->new();
        my $state = $statem->get_init_state($world);
        $statem->init_state_analyze( $world, $state );    #modifies $world

        my @roles = @{ $world->{facts}->{role} };
        for my $i ( 0 .. $#roles ) {
            print( $roles[$i] // '__UNDEF__' ) . ' = '
                . ( $agents[$i] // '__UNDEF__' ) . "\n";

            #            $result{goals}->[$i].' = '.$result{$roles[$i]};
        }
        my $stoptime = time()+60 * $opts->{timed};
        my $gamecounter = 0;
        while (time()<$stoptime) {
            %result = run_match( $world, $state, $opts, @agents );
            $gamecounter++;
            print $gamecounter."\n" if $gamecounter % 10 == 0;
        }
        print "\n$gamecounter times in ".$opts->{timed}." minutes. ".$gamecounter/$opts->{timed} . " per minute\n" ;

    } else {
        if ( $opts->{server} || $opts->{quiet} ) {
            logdest('file');
            my $logfile = $homedir . '/log/ggp-match.log';
            if ( -f $logfile ) {
                unlink($logfile);
            }
            logfile($logfile);
        }
        my @agents = ();
        my %result;
        if ( $opts->{agents} ) {
            @agents = $opts->{agents} ? split( /\,/, $opts->{agents} ) : ();
        }
        if ( $opts->{duplex} ) {
            my @results = ();
            my %rolemap;
            my $world = parse_gdl_file( $opts->{rulefile}, $opts );
            $world = GGP::Tools::RuleOptimizer::optimize_rules($world);

            my $statem = GGP::Tools::StateMachine->new();
            my $state = $statem->get_init_state($world);
            $statem->init_state_analyze( $world, $state );    #modifies $world
            my @roles = @{ $world->{roles} };
            for my $i ( 0 .. $#roles ) {
                print $roles[$i] . ' = ' . $agents[$i] . "\n";
                $rolemap{ $roles[$i] } = $agents[$i];
            }
            %result = run_match( $world, $state, $opts, @agents );

            my %output;
            while ( my ( $key, $value ) = each(%rolemap) ) {
                $output{$value} = $result{$key};
                $output{$key}   = $value;
            }
            push( @results, dclone( \%output ) );

            # second iteration

            %output  = ();
            %rolemap = ();
            @agents  = reverse @agents;
            @roles   = @{ $world->{roles} };
            for my $i ( 0 .. $#roles ) {
                print $roles[$i] . ' = ' . $agents[$i] . "\n";
                $rolemap{ $roles[$i] } = $agents[$i];
            }
            %result = run_match( $world, $state, $opts, @agents );
            while ( my ( $key, $value ) = each(%rolemap) ) {
                $output{$value} = $result{$key};
                $output{$key}   = $value;
            }
            push( @results, \%output );

            #        push(@results, \%results2);
            my @colorder = ( @roles, @agents );
            my $rs = rs_convert_from_hashes( \@results, \@colorder );
            print rs_pretty_format_table($rs);
            my %agrcol;
            for my $role (@agents) {
                $agrcol{$role} = 'sum';
            }
            my $aggr_rs = rs_aggregate( $rs, { aggregation => \%agrcol } );
            print rs_pretty_format_table($aggr_rs);

        }
        else {    #single
            my $statem = GGP::Tools::StateMachine->new();
            my $world = parse_gdl_file( $opts->{rulefile}, $opts );
            $world = GGP::Tools::RuleOptimizer::optimize_rules($world);

            my $state = $statem->get_init_state($world);
            $statem->init_state_analyze( $world, $state );    #modifies $world

            my @roles = @{ $world->{facts}->{role} };
            for my $i ( 0 .. $#roles ) {
                print( $roles[$i] // '__UNDEF__' ) . ' = '
                . ( $agents[$i] // '__UNDEF__' ) . "\n";

                #            $result{goals}->[$i].' = '.$result{$roles[$i]};
            }

            %result = run_match( $world, $state, $opts, @agents );
    #        print Dumper %result;
        }
    }
}

sub _order_match {

}

__PACKAGE__->new->main;


=head1 AUTHOR

Slegga

=cut

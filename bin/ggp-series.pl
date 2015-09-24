#!/usr/bin/env perl
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use feature 'say';
use File::Slurp;
use Storable qw(dclone);
use List::Util qw(reduce);

=encoding utf8

=head1 NAME

ggp-series.pl

=head1 DESCRIPTION

Run many matches in series.

Output total points.

=cut

my $homedir;
my $gdescfile = 'tictactoe0';
my @movehist;

use Cwd 'abs_path';
BEGIN {
    $homedir = abs_path($0);
    $homedir =~s|[^\/\\]+[\/\\][^\/\\]+$||;
}
use lib "$homedir/lib";
use GGP::Tools::Match qw( run_match list_rules list_agents);
use SH::Script qw( options_and_usage );
use GGP::Tools::Parser qw ( parse_gdl_file);
use GGP::Tools::StateMachine;
use GGP::Tools::Utils qw (logdest logfile);
use SH::ResultSet qw(rs_convert_from_hashes rs_pretty_format_table rs_aggregate);

my @ARGV_COPY = @ARGV;
my ( $opts, $usage ) = options_and_usage(
    $0,
    \@ARGV,
    "%c %o",
    [ 'info|i!',        'Info of rules and agents' ],
    [ 'rulefiles|r=s',  'Name of rule files comma separated' ],
    [ 'agents|a=s',     'A list of agents comma separated (guidedf,guidedl)' ],
    [ 'quiet|q!',       'Print only result' ],
    [ 'verbose|v!',     'Print log info' ],
    [ 'watch|w=s',      'Comma separated list of state keys to watch' ],
    [ 'iterations|t=n', 'Max states calculated' ],
);

if ( $opts->{info} ) {
    print "\nrules:\n " . join( "\n ", list_rules() );
    print "\n\n";
    print "agents:\n " . join( "\n ", list_agents() );
    print "\n\n";
    if ( $opts->{verbose} ) {
        my @allrules = list_rules();
        my @output   = ();
        for my $rule (@allrules) {
            my $world = parse_gdl_file( $rule, { server => 1 } );

            my $state = get_init_state($world);
            init_state_analyze( $world, $state );    #modifies $world
            my $tmp = $world->{analyze};

            #print "$rule: ".Dumper $world->{analyze};
            $tmp->{rule} = $rule;
            push( @output, $tmp );

        }
        my $rs = rs_convert_from_hashes( \@output, [ 'rule', 'noofroles', 'firstmoves', 'goalheuristic' ] );
        print rs_pretty_format_table($rs);

    }
} else {
    if ( $opts->{server} || $opts->{quiet} ) {
        logdest('file');
        my $logfile = $homedir . '/log/ggp-match.log';
        if ( -f $logfile ) {
            unlink($logfile);
        }
        logfile($logfile);
    }
    my @rules = split( /\,/, $opts->{rulefiles} );

    my %result;
    my @agents = split( /\,/, $opts->{agents} );
    my @matches = @{ cartesian_product( \@agents, \@agents, \@rules ) };
    my @results = ();
    for my $match (@matches) {
        next if $match->[0] eq $match->[1];
        my %rolemap;
# warn Dumper $match;
        my $rulefile = $match->[2];
        my $world = parse_gdl_file( $rulefile, $opts );
        my $statem = GGP::Tools::StateMachine->new();
        my $state = $statem->get_init_state($world);
        $statem->init_state_analyze( $world, $state );    #modifies $world
        my @roles = @{ $world->{facts}->{role} };
        $rolemap{ $roles[0] } = $match->[0];
        $rolemap{ $roles[$#roles] } = $match->[1];
        if ( @roles == 1 ) {
            confess "No support for single";
        } elsif ( @roles > 2 ) {
            confess "Max 2";
        }

        %result = run_match( $world, $state, $opts, $match->[0], $match->[1] );
        my %output;
        $output{rule} = $rulefile;
        while ( my ( $key, $value ) = each(%rolemap) ) {
            $output{$value} = $result{$key};
            $output{$key}   = $value;
        }
        push( @results, dclone( \%output ) );

    }
    my @colorder = ( 'rule', @agents );
    my $rs = rs_convert_from_hashes( \@results, \@colorder );
    print rs_pretty_format_table($rs);
    my %agrcol;
    for my $role (@agents) {
        $agrcol{$role} = 'sum';
    }
    my $aggr_rs = rs_aggregate( $rs, { aggregation => \%agrcol } );
    print rs_pretty_format_table( $aggr_rs, { null => ' ' } );
}

sub cartesian_product {
#    reduce {
#        [   map {
#                my $item = $_;
#                map [ @$_, $item ], @$a
#            } @$b
#        ];
#    }
#    [ [] ], @_;
#}
my $last = pop @_;

unless(@_) {
       return map([$_], @$last);
}

return map {
             my $left = $_;
             map([@$left, $_], @$last)
           }
           cartesian_product(@_);
}
=head1 AUTHOR

Slegga

=cut

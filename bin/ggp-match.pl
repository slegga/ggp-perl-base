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

ggp-match.pl - run a match CLI

=head1 DESCRIPTION

Run one match with given inputs

=cut

# Enable warnings within the Parse::RecDescent module.
my $homedir;
my $gdescfile = 'tictactoe0';
my @movehist;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    }
    else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";
use SH::GGP::Tools::Match qw ( run_match list_rules list_agents);
use SH::Script qw( options_and_usage );
use SH::GGP::Tools::Parser qw ( parse_gdl_file);
use SH::GGP::Tools::StateMachine qw ( get_init_state  init_state_analyze);
use SH::GGP::Tools::Utils qw (logdest logfile);
use SH::ResultSet
  qw(rs_convert_from_hashes rs_pretty_format_table rs_aggregate);

my @ARGV_COPY = @ARGV;
my ( $opts, $usage ) = options_and_usage(
    $0,
    \@ARGV,
    "%c %o",
    [ 'info|i!', 'Info of rules and agents' ],
    [ 'rulefile|r=s', 'Name og rule file', { 'default' => $gdescfile } ],
    [ 'agents|a=s',     'A list of agents comma separated (guidedf,guidedl)' ],
    [ 'duplex|d!',      'Run a match where each particitant try each role' ],
    [ 'quiet|q!',       'Print only result' ],
    [ 'verbose|v!',     'Print log info' ],
    [ 'watch|w=s',      'Comma separated list of state keys to watch' ],
    [ 'server|s',       'Print data to file' ],
    [ 'iterations|t=n', 'Max states calculated' ],
    [ 'timed=n',        'Count how many games in n minutes.', ],
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
        my $rs = rs_convert_from_hashes( \@output,
            [ 'rule', 'noofroles', 'firstmoves', 'goalheuristic' ] );
        print rs_pretty_format_table($rs);

    }
}
elsif ( $opts->{timed} ) {
    die "Unimplemented";

    # Run same game again and again until time is up.
    # Count number of games.
}
else {
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

        my $state = get_init_state($world);
        init_state_analyze( $world, $state );    #modifies $world
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
        my $world = parse_gdl_file( $opts->{rulefile}, $opts );
        my $state = get_init_state($world);
        init_state_analyze( $world, $state );    #modifies $world

        my @roles = @{ $world->{roles} };
        for my $i ( 0 .. $#roles ) {
            print( $roles[$i] // '__UNDEF__' ) . ' = '
              . ( $agents[$i] // '__UNDEF__' ) . "\n";

            #            $result{goals}->[$i].' = '.$result{$roles[$i]};
        }

        %result = run_match( $world, $state, $opts, @agents );
        print Dumper %result;
    }
}

sub _order_match {

}

=head1 AUTHOR

Slegga

=cut

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

#use lib "$homedir/lib";
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../utilities-perl/lib";
use GGP::Tools::Match qw( run_match list_rules list_agents);
#use SH::Script qw( options_and_usage );
use SH::ScriptX;
use Mojo::Base 'SH::ScriptX';
use GGP::Tools::Parser qw ( parse_gdl_file);
use GGP::Tools::StateMachine;
use GGP::Tools::Utils qw (logdest logfile);
# use SH::ResultSet qw(rs_convert_from_hashes rs_pretty_format_table rs_aggregate);
use SH::PrettyPrint;

#my @ARGV_COPY = @ARGV;
#my ( $opts, $usage ) = options_and_usage(
#    $0,
#    \@ARGV,
#    "%c %o",

option    'info!',        'Info of rules and agents';
option    'rulefiles=s',  'Name of rule files comma separated';
option    'agents=s',     'A list of agents comma separated (guidedf,guidedl)';
option    'quiet!',       'Print only result';
option    'verbose!',     'Print log info';
option    'watch=s',      'Comma separated list of state keys to watch';
option    'iterations=i', 'Max states calculated';


sub main {
	my $self = shift;
	my $opts;
    for my $ar(qw/info rulefiles agents quiet verbose watch iterations/) {
        $opts->{$ar} = $self->$ar;
    }

    if ( $self->info ) {
	    print "\nrules:\n " . join( "\n ", list_rules() );
	    print "\n\n";
	    print "agents:\n " . join( "\n ", list_agents() );
	    print "\n\n";
	    if ( $self->verbose ) {
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
	#        my $rs = rs_convert_from_hashes( \@output, [ 'rule', 'noofroles', 'firstmoves', 'goalheuristic' ] );
	#        print rs_pretty_format_table($rs);
			SH::PrettyPrint::print_hashes(\@output);
	    }
	} else {
	    if (  $opts->{server} || $opts->{quiet} ) {
	        logdest('file');
	        my $logfile = $homedir . '/log/ggp-match.log';
	        if ( -f $logfile ) {
	            unlink($logfile);
	        }
	        logfile($logfile);
	    }
	    my @rules;
		@rules = split( /\,/, $opts->{rulefiles} ) if $opts->{rulefiles};

	    my %result;
	    my @agents;
	    @agents = split( /\,/, $opts->{agents} ) if $self->agents;
	    my @matches = cartesian_product( \@agents, \@agents, \@rules );
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
	    SH::PrettyPrint::print_hashes(\@results);
	}
}

sub cartesian_product {
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

__PACKAGE__->new->main;


=head1 AUTHOR

Slegga

=cut

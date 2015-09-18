#!/usr/bin/env perl
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use feature 'say';
use File::Slurp;
use Storable qw(dclone);
use List::MoreUtils qw(any first_index);

=encoding utf8

=head1 NAME

ggp-report.pl - run series

=head1 DESCRIPTION

Run series of matches to figure out what is best.

=cut

# Enable warnings within the Parse::RecDescent module.
my $homedir;
my $gdescfile = 'tictactoe0';
my @movehist;
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
use GGP::Tools::Match qw (run_match list_rules list_agents);
use SH::Script qw(options_and_usage);

my @ARGV_COPY = @ARGV;
my ( $opts, $usage ) = options_and_usage(
    $0,
    \@ARGV,
    "%c %o",
    [ 'info|i!',       'Info of rules and agents' ],
    [ 'rulefiles|r=s',  'Names of rule files comma separated' ],
    [ 'agents|a=s',    'A list of agents comma separated (guidedf,guidedl)' ],
    [ 'epocfrom=n',    'Show only result from after from epoc' ],
);

if ($opts->{info}) {
    print "\nrules:\n ".join("\n ",list_rules() );
    print "\n\n";
    print "agents:\n ".join("\n ",list_agents() );
    print "\n\n";
} else {
    print time()."\n";
    if (! -e $homedir . "/log/ggp-results.txt") {
        `touch $homedir/log/ggp-results.txt`;
    }
    my $datatext = read_file($homedir . "/log/ggp-results.txt");
    $datatext = "( ".$datatext." )";
    my @data = eval($datatext);
    #print Dumper @data;

    # calculate failed rules %
    for my $rule(list_rules) {
        my $tot=0;
        my $fail=0;
        for my $m(@data){
            if ($opts->{fromepoc} &&  $opts->{fromepoc} > $m->{epoc}) {
                next;
            }
            if ($m->{rule} eq $rule) {
                $tot++;
                if ($m->{status} eq 'failed') {
                    $fail++;
                }
            }
        }
        if ($tot ) {
            printf "%20s Tot: %4d %2.1d %%\n",$rule, $tot, 100 * $fail / $tot;
        }
    }
    print "\n\n";
    # calculate failed ag %
    for my $agent(list_agents) {
        my $tot=0;
        my $fail=0;
        my $sum=0;
        for my $m(@data){
            if ($opts->{fromepoc} &&  $opts->{fromepoc} > $m->{epoc}) {
                next;
            }
            if (any {$_ eq $agent} @{$m->{particiants}}) {
                $tot++;
                if ($m->{status} eq 'failed') {
                    $fail++;
                } elsif ($m->{status} eq 'finished') {
                    my $idx = first_index{$_ eq $agent} @{$m->{particiants}};
                    $sum += $m->{goals}->[$idx] if exists $m->{goals} ;
                }
            }
        }
        if ($tot ) {
            printf "%20s Tot: %4d %2.1d %3.1d\n",$agent, $tot, 100 * $fail / $tot, $sum / $tot;
        }
    }

    # calc success
}

=head1 AUTHOR

Slegga

=cut

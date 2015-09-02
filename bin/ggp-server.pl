#!/usr/bin/env perl
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use feature 'say';
use File::Slurp;
use List::MoreUtils qw(none any);
use Storable qw(dclone);


# use Proc::Background;

=encoding utf8

=head1 NAME

ggp-server.pl - Think this script is obsolete (18/6-2015)

=head1 DESCRIPTION

Set up matches.

=head1 server

Test out creating sub processes.
Wait. Report if success or not.
Handle time out.

Print to catalog ...

=cut

my $homedir;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";
use SH::GGP::Tools::Match qw (run_match list_rules list_agents get_number_of_paricipants);
use SH::GGP::Tools::Utils qw (logf store_result logdest logfile);
use SH::GGP::Tools::Parser qw (parse_gdl_file);
use SH::Script qw(options_and_usage);
use SH::GGP::Tools::StateMachine qw ( get_init_state);


sub timed_out {
    die "GOT TIRED OF WAITING";
}

my @ARGV_COPY = @ARGV;
my ( $opts, $usage ) = options_and_usage(
    $0,
    \@ARGV,
    "%c %o",
    [ 'info|i!',       'Info' ],
    [ 'rulefiles|r=s', 'Name of rulefiles, sepeated by ,' ],
    [ 'agents|a=s',    'A list of agents comma separated (guidedf,guidedl)' ],
    [ 'verbose|v!',    'Print some to screen else only print to files.' ],
);

if ( $opts->{info} ) {
    print "\nrules:\n " . join( "\n ", list_rules() );
    print "\n\n";
    print "agents:\n " . join( "\n ", list_agents() );
    print "\n\n";
} else {
    print time() . "\n";
    $SIG{ALRM} = \&timed_out;
    my @rulepool = list_rules();
    @rulepool = grep { $_ ne 'proptest' } @rulepool;    # noworking files
    if ( $opts->{rulefiles} ) {
        my @finalrulefiles;
        my @tmpoptsrules = split( /\,/, $opts->{rulefiles} );
        for my $file (@tmpoptsrules) {
            if ( any { $_ eq $file } @rulepool ) {
                push( @finalrulefiles, $file );
            }
        }

        #        warn "fina".Dumper @finalrulefiles;
        #        warn "opts".Dumper @tmpoptsrules;

        if (@finalrulefiles) {
            @rulepool = @finalrulefiles;
        }
    }
    if ( $opts->{verbose} ) {
        warn "Use " . join( ', ', @rulepool );
    }

    my @agentpool = list_agents();
    @agentpool = grep {
        my $c = $_;
        none { $c eq $_ } ( 'CompulsiveDeliberation', 'MCTSLight' )
    } @agentpool;    # noworking agents
    if ( $opts->{agents} ) {
        my @finalagents;
        my @tmpoptsagents = split( /\,/, $opts->{agents} );
        for my $file (@tmpoptsagents) {
            if ( any { $_ eq $file } @agentpool ) {
                push( @finalagents, $file );
            }
        }
        if (@finalagents) {
            @agentpool = @finalagents;
            if ( $opts->{verbose} ) {
                print "Use " . join( ', ', @agentpool );
            }
        }
    }

    logdest('file');
    logfile( $homedir . '/log/ggp-server.log' );
    while (1) {
        my $rulefile    = $rulepool[ rand @rulepool ];
        my @particiants = ();
        my %result;
        $opts->{server} = 1;
        my $world = parse_gdl_file( $rulefile, $opts );
        my $state = get_init_state($world);

        my @roles = get_number_of_paricipants( { rulefile => $rulefile } );

        #choose agents
        for (@roles) {
            my $candidate;
            while (1) {
                $candidate = $agentpool[ rand @agentpool ];
                my $agent = 'SH::GGP::Agents::' . $candidate;
                if ( !eval "require $agent" ) {
                    confess("Failed to load plugin: $agent $@");

                }
                my $agentcode = $agent->new();

                if ( exists $agentcode->{minnoofroles} && $agentcode->{minnoofroles} > $world->{analyze}->{noofroles} )
                {
                    confess "Can not choose a proper candidate" if scalar @agentpool < 2;
                    next;
                }
                if ( exists $agentcode->{maxnoofroles} && $agentcode->{maxnoofroles} < $world->{analyze}->{noofroles} )
                {
                    confess "Can not choose a proper candidate" if scalar @agentpool < 2;
                    next;
                }
                last;
            }
            push @particiants, $candidate;
        }
        logf( 'ggp-match.pl -r ' . $rulefile . ' -a ' . join( ',', @particiants ) );
        my $tmpepoc = time();
        alarm( 30 * 60 * 60 );
        eval { %result = run_match( $world, $state, { rulefile => $rulefile, server => 1 }, @particiants ); };
        alarm(0);    # Cancel the pending alarm if user responds.
        $result{epoc}        = $tmpepoc;
        $result{rule}        = $rulefile;
        $result{particiants} = \@particiants;

        # print "epoc:".$result{'epoc'};
        $result{'time'} = ( time() - $result{'epoc'} );
        for my $i ( 0 .. $#roles ) {
            $result{roles}->{ $roles[$i] } = $particiants[$i];
            $result{goals}->[$i] = $result{ $roles[$i] };
        }

        if ( $@ =~ /GOT TIRED OF WAITING/ ) {
            $result{status} = 'timedout';
        } elsif ($@) {
            $result{status} = 'failed';
            $result{message} = substr( $@, 0, 150 );
            $result{message} =~ s/$homedir//g;
            $result{message} =~ s!/lib/SH/GGP!!g;
            $result{message} =~ s!/bin!!g;
            $result{message} =~ s!/\n.*!!smg;
            logf($@);
        } else {
            $result{status} = 'finished';
        }
        store_result(%result);
    }
}

#     while(1) {
#         my $proc1 = Proc::Background->new("$homedir/bin/ggp-match.pl",'data');
#         while ($proc1->alive) {
#
#         }
#
#     }

=head1 AUTHOR

Slegga

=cut


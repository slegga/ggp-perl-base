package SH::GGP::Tools::Match;
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use File::Slurp;
use Exporter 'import';
use Storable qw(dclone);
use List::MoreUtils qw(any uniq first_index none);
use utf8;
use open ':locale';#gives out as locale

=encoding utf8

=head1 NAME

SH::GGP::Tools::Match

=head1 SYNOPSIS

 use SH::GGP::Tools::Match qw(list_rules);
 print join("\n",list_rules());

=head1 DESCRIPTION

Match facilitator module.

=head1 METHODS

=cut

# Enable warnings within the Parse::RecDescent module.
my $homedir;
my $gdescfile = 'tictactoe0.kif';
BEGIN {
    if ($^O eq 'MSWin32') {
        $homedir = 'c:\privat';
    } else {
        $homedir = $ENV{HOME};
    }
}
use lib "$homedir/git/ggp-perl-base/lib";
use SH::GGP::Tools::StateMachine qw ( process_move );
use SH::GGP::Tools::Parser qw(parse_gdl);
use SH::GGP::Agents::Random; #qw (info start play stop abort);
use SH::GGP::Agents::Guided;#  qw (info start play stop abort);
use SH::GGP::Tools::Utils  qw( hashify extract_variables data_to_gdl logf);
use SH::Script qw(options_and_usage);
our @EXPORT_OK = qw(run_match list_rules list_agents get_number_of_paricipants);

=head2 list_rules

Return an array with all rule names.

=cut

sub list_rules {
    my $path = "$homedir/Dropbox/data/kif/";
    my $type = '.kif';
    my @rulefiles = glob( $path."*".$type);
    @rulefiles = map {s/^$path//;$_} @rulefiles;
    @rulefiles = map {s/$type$//;$_} @rulefiles;
    return @rulefiles;
}

=head2 list_agents

Return an array with all agent names.

=cut


sub list_agents {
    my $path = "$homedir/lib/SH/GGP/Agents/";
    my $type = '.pm';
    my @agents = glob( $path."*".$type);
    @agents = map {s/^$path//;$_} @agents;
    @agents = map {s/$type$//;$_} @agents;

    return @agents;
}

=head2 get_number_of_paricipants

Return an array of role names

=cut

sub get_number_of_paricipants {
    my $opts = shift;
    my $rulefile = $opts->{rulefile};
    my $gdlfile = "$homedir/Dropbox/data/kif/".$rulefile.".kif";
    my $textrules= read_file($gdlfile);
    my $world = parse_gdl($textrules, $opts);
    return @{$world->{roles}};
}

=head2 run_match

Run a complete match.
Return an hash with results like goals

=cut


sub run_match {
    my $world = shift;
    my $state = shift;
    my $opts = shift;
    my @movehist;

#    my $rulefile = $opts->{rulefile};
    my @particiants = @_;
    my $id='test';

    my @roles=();
    my $i=0;
    for my $rname(@{$world->{roles}}) {
        $roles[$i]{name} = $rname;
        if ($particiants[$i]) {
            if ($particiants[$i] eq 'guidedf') {
                $roles[$i]{agent} = SH::GGP::Agents::Guided->new();
            } elsif ($particiants[$i] eq 'guidedl') {
                $roles[$i]{agent} = SH::GGP::Agents::Guided->new(13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13);
            } else {
                my $agent = 'SH::GGP::Agents::'.$particiants[$i];
                if (! eval "require $agent") {
                    confess("Failed to load plugin: $agent $@");

                }
                $roles[$i]{agent} = $agent->new();
            }
            $i++;
        } else {
            $roles[$i]{agent} = SH::GGP::Agents::Random->new();
            $i++;
        }
    }

    for my $r(0 .. $#roles) {
        logf data_to_gdl( $roles[$r]{agent}->info);
    }

    for my $r(0 .. $#roles) {
        logf Dumper $roles[$r]{agent}->start($id,$world->{roles}->[$r],$world,15,15,$opts->{iterations});
    }


    $i=0;
    my $continue=1;
    my $moves = 'nil';
    my $newmoves=();
    while ( $continue) {
        for my $r(0 .. $#roles) {
            $newmoves->[$r] = $roles[$r]{agent}->play($id,$moves,$state);
            if (!defined $newmoves->[$r]) {
                logf( data_to_gdl($state));
                confess "Unexpected undef \$newmoves for ". $roles[$r]{name};
            }
        }
    #    logf Dumper $newmoves; #[mark=>[1,1],noop]
        $moves=dclone $newmoves;
        $state = process_move($world, $state, $newmoves);
        push (@movehist, $moves);
        $i++;
        if (exists $state->{'terminal'}) {
            $continue=0;
        }
        if ($i > 400) {
            logf( Dumper $state );
            confess "More than 100 iterations";
        }
        my $output=data_to_gdl($moves);
        if ($opts->{watch}) {
            for my $key(split(/,/,$opts->{watch})) {
                if (exists $state->{$key} ) {
                    $output .= " $key:".data_to_gdl( $state->{$key});
                }
            }
        }
        logf($output);
    }
    for my $r(0 .. $#roles) {
        logf (Dumper $roles[$r]{agent}->stop);
    }

    logf data_to_gdl( $state) if $opts->{verbose};
    logf( " TURNS: $i");
    #print "\nACTIONS:\n";
    #print data_to_gdl($_)."\n" for(@movehist);
    logf( "\nFINAL RESULT:\n");

    #print only goals for roles
    for my $goal(@{$state->{goal}}) {
        if (any {$goal->[0] eq $_} @{$state->{role}} ) {
            logf( data_to_gdl($goal)."\n" );
        }
    }
    my %return = %{hashify(@{$state->{goal}})};
    # warn Dumper %return;
    # remove return{goal}{b};
    for my $key(reverse keys %return) {
        if (none{$key eq $_} @{$world->{roles}}) {
            delete $return{$key};
        }
    }
    return %return;
}
1;

=head1 AUTHOR

Slegga

=cut


package GGP::Tools::Match;
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

GGP::Tools::Match

=head1 SYNOPSIS

 use GGP::Tools::Match qw(list_rules);
 print join("\n", list_rules());

=head1 DESCRIPTION

Utility module for running a match.

=head1 METHODS

=cut

# Enable warnings within the Parse::RecDescent module.
my $homedir;
my $gdescfile = 'tictactoe0.kif';
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
use GGP::Tools::StateMachine (); #qw ( process_move);
use GGP::Tools::Parser qw(parse_gdl);
use GGP::Agents::Random; #qw (info start play stop abort);
use GGP::Agents::Guided;#  qw (info start play stop abort);
use GGP::Tools::Utils  qw( hashify extract_variables data_to_gdl logf);
our @EXPORT_OK = qw(run_match list_rules list_agents get_number_of_participants);

=head2 list_rules

List available rules.
Placed in the correct directory.

=cut


sub list_rules {
    my $path = "$homedir/share/kif/";
    my $type = '.kif';
    my @rulefiles = glob( $path."*".$type);
    @rulefiles = map {s/^$path//;$_} @rulefiles;
    @rulefiles = map {s/$type$//;$_} @rulefiles;
    return @rulefiles;
}

=head2 list_agents

List available agents.
Placed in the correct directory.

=cut

sub list_agents {
    my $path = "$homedir/lib/GGP/Agents/";
    my $type = '.pm';
    my @agents = glob( $path."*".$type);
    @agents = map {s/^$path//;$_} @agents;
    @agents = map {s/$type$//;$_} @agents;

    return @agents;
}

=head2 get_number_of_participants

Get number of participants

=cut

sub get_number_of_participants {
    my $opts = shift;
    my $rulefile = $opts->{rulefile};
    my $gdlfile = "$homedir/Dropbox/data/kif/".$rulefile.".kif";
    my $textrules= read_file($gdlfile);
    my $world = parse_gdl($textrules, $opts);
    return @{$world->{facts}->{role}};
}

=head2 run_match

Run a complete match. Return results like goals, turns, time ++.

=cut

sub run_match{
    my $world = shift;
    my $state = shift;
    my $opts = shift;
    my @movehist;

#    my $rulefile = $opts->{rulefile};
    my @particiants = @_;
    my $id='test';

    if ($opts->{verbose}) {
        my $output="\nWORLD\n";
        for my $part(sort {$b cmp $a} keys %$world) {
            $output .= "\n$part:\n";
            if (ref $world->{$part} eq 'HASH') {
                while (my ($key, $value) = each(%{$world->{$part}})) {
                    if (exists $state->{$key} ) {
                        $output .= "$key:".data_to_gdl( $value )."\n";
                    }
                }
            } else {
                for my $line (@{$world->{$part}}) {
                    $output .= sprintf "%s : %s\n",data_to_gdl( $line->{effect} ),data_to_gdl( $line->{criteria} ),;
                }
            }
        }

        logf($output);
    }


    my @roles=();
    my $i=0;
    for my $rname(@{$world->{facts}->{role}}) {
        $roles[$i]{name} = $rname;
        if ($particiants[$i]) {
            if ($particiants[$i] eq 'guidedf') {
                $roles[$i]{agent} = GGP::Agents::Guided->new();
            } elsif ($particiants[$i] eq 'guidedl') {
                $roles[$i]{agent} = GGP::Agents::Guided->new(13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13);
            } else {
                my $agent = 'GGP::Agents::'.$particiants[$i];
                if (! eval "require $agent") {
                    confess("Failed to load plugin: $agent $@");

                }
                $roles[$i]{agent} = $agent->new();
            }
            $i++;
        } else {
            $roles[$i]{agent} = GGP::Agents::Random->new();
            $i++;
        }
    }

    for my $r(0 .. $#roles) {
        logf data_to_gdl( $roles[$r]{agent}->info);
    }

    for my $r(0 .. $#roles) {
        logf Dumper $roles[$r]{agent}->start($id,$world->{facts}->{role}->[$r],$world,15,15,$opts->{iterations});
    }


    # MAIN LOOP FOR GAMES

    my $statem = GGP::Tools::StateMachine->new($world, \@roles);
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
        $state = $statem->process_move($world, $state, $newmoves);
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
                    $output .= "\n$key:".data_to_gdl( $state->{$key});
                }
            }
        }
        logf($output);
    }
    for my $r(0 .. $#roles) {
        logf (Dumper $roles[$r]{agent}->stop);
    }
    if ($opts->{verbose}) {
        my $output='';
        my @factf = keys %{$world->{facts}};
        for my $key(%$state) {
            next if any {$key eq $_} @factf;
            if (exists $state->{$key} ) {
                $output .= "\n$key:".data_to_gdl( $state->{$key});
            }
        }

        logf($output);
    }
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
        if (none{$key eq $_} @{$world->{facts}->{role}}) {
            delete $return{$key};
        }
    }
    return %return;
}
1;

=head1 AUTHOR

Slegga

=cut

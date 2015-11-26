#!/usr/bin/env perl
use strict qw(vars);
use warnings;
use autodie;
use Data::Dumper;
use Carp;
use feature 'say';
use File::Slurp;
use Cwd 'abs_path';
use Storable qw(dclone);
use Test::More;
use List::MoreUtils qw (none any );
#use Test::More;   # instead of tests => 32
my $homedir;
my $gdescfile = 'tictactoe0.kif';
my @movehist;
BEGIN {
    $homedir = abs_path($0);
    $homedir =~s|[^\/\\]+[\/\\][^\/\\]+$||;
}

# perldebug t/ggp-gdl-parser-order.t


use lib "$homedir/lib";

use GGP::Tools::Parser (parse_gdl);

sub get_check_parser_order {
    my $gdlfilepath = shift;
    my $text        = read_file("$homedir/share/kif/$gdlfilepath.kif");
    my @gdllines = GGP::Tools::Parser::gdl_concat_lines($text);
    my @gdllines2;
    for my $gdlline (@gdllines) {
        next if ! $gdlline;
        next if any { $gdlline =~ /$_/i} (qr/\bbase\b/,qr/\binput\b/,qr/\;/);
        push(@gdllines2, $gdlline);
    }
    my $norows = @gdllines2;
    my $gdl = GGP::Tools::Parser::gdl_order_and_group_lines( @gdllines );
    my $afternorows = @{$gdl->{facts}} + @{$gdl->{init}} + @{$gdl->{'next'}} + @{$gdl->{body}} + @{$gdl->{legal}} + @{$gdl->{goal}} + @{$gdl->{terminal}};
    is ($afternorows, $norows, 'Have the right number of rows after ordering');
    my $test =1;
    # Next test
    # FIXME
    # Next is hard to test.
    # Remove comment code below and do something similar in a new test file for a finished world "object" in data format.
    #
#    my @known = grep {defined} map{$_=~/([\w\+]+)/;$1} @{$gdl->{facts}};
#    push @known,grep {defined} map{$_=~/([\w\+]+)/;$1} @{$gdl->{init}};
#    push @known,'true','not','distinct','or';
#    for my $i (0 .. $#{$gdl->{next}}) {
#        my $line = $gdl->{next}->[$i];
#        my @lwords = ($gdl->{next}->[$i] =~ /[^?]\b([\w\+]+)/g);
#        if ($lwords[0] eq 'next') {
#            shift @lwords;
#            my $next = shift @lwords;
#            if (! any { $next eq $_ } @known ) {
#                push(@known, $next);
#            }
#        }
#        for my $lword (@lwords) {
#            if (none {$lword eq $_ } @known) {
#               $test = 0;
#                warn "next";
#                warn "Error on word: ". $lword;
#                warn "Error on line: ". $gdl->{next}->[$i];
#                warn Dumper $gdl->{next};
#            }
#        }
#    }

    # Body test
    for my $i (0 .. $#{$gdl->{body}}) {
	my $line = $gdl->{body}->[$i];
 	my ($word) = ($gdl->{body}->[$i] =~ /([\w\+]+)/);
	for my $j(0 .. $i) {
	    next if $j == $i;
     	if ($gdl->{body}->[$j] =~ /[\w\+]+.+\b$word\b/) {
		$test=0;
		warn "Error on word: ". $word;
		warn "Error on line: ". $gdl->{body}->[$j];
		warn Dumper $gdl->{body};
	    }
	}
    }
    ok ($test, 'Right order of lines');
}

opendir(my $dh,"$homedir/share/kif") || die "can't opendir $homedir/share/kif: $!";
my @rulefiles = readdir( $dh );
for my $file(@rulefiles) {
    next if $file !~ /\.kif$/;

    $file =~ s/\.kif$//;
    diag "$file";
    get_check_parser_order( $file );
}
closedir $dh;
my $gdl='( START Base.ticTicToe.1448516596050 xplayer (( role xplayer ) ( role oplayer ) ( <= ( base ( cell ?m ?n x ) ) ( index ?m ) ( index ?n ) ) ( <= ( base ( cell ?m ?n o ) ) ( index ?m ) ( index ?n ) ) ( <= ( base ( cell ?m ?n b ) ) ( index ?m ) ( index ?n ) ) ( base ( control white ) ) ( base ( control black ) ) ( base ( step 1 ) ) ( <= ( base ( step ?n ) ) ( succ ?m ?n ) ) ( <= ( input ?p ( mark ?m ?n ) ) ( index ?m ) ( index ?n ) ( role ?p ) ) ( index 1 ) ( index 2 ) ( index 3 ) ( init ( cell 1 1 b ) ) ( init ( cell 1 2 b ) ) ( init ( cell 1 3 b ) ) ( init ( cell 2 1 b ) ) ( init ( cell 2 2 b ) ) ( init ( cell 2 3 b ) ) ( init ( cell 3 1 b ) ) ( init ( cell 3 2 b ) ) ( init ( cell 3 3 b ) ) ( init ( step 1 ) ) ( <= ( next ( cell ?j ?k x ) ) ( true ( cell ?j ?k b ) ) ( does xplayer ( mark ?j ?k ) ) ( does oplayer ( mark ?m ?n ) ) ( or ( distinct ?j ?m ) ( distinct ?k ?n ) ) ) ( <= ( next ( cell ?m ?n o ) ) ( true ( cell ?m ?n b ) ) ( does xplayer ( mark ?j ?k ) ) ( does oplayer ( mark ?m ?n ) ) ( or ( distinct ?j ?m ) ( distinct ?k ?n ) ) ) ( <= ( next ( cell ?m ?n b ) ) ( true ( cell ?m ?n b ) ) ( does xplayer ( mark ?m ?n ) ) ( does oplayer ( mark ?m ?n ) ) ) ( <= ( next ( cell ?p ?q b ) ) ( true ( cell ?p ?q b ) ) ( does xplayer ( mark ?j ?k ) ) ( does oplayer ( mark ?m ?n ) ) ( or ( distinct ?j ?p ) ( distinct ?k ?q ) ) ( or ( distinct ?m ?p ) ( distinct ?n ?q ) ) ) ( <= ( next ( cell ?m ?n ?w ) ) ( true ( cell ?m ?n ?w ) ) ( distinct ?w b ) ) ( <= ( next ( step ?y ) ) ( true ( step ?x ) ) ( succ ?x ?y ) ) ( succ 1 2 ) ( succ 2 3 ) ( succ 3 4 ) ( succ 4 5 ) ( succ 5 6 ) ( succ 6 7 ) ( <= ( row ?m ?x ) ( true ( cell ?m 1 ?x ) ) ( true ( cell ?m 2 ?x ) ) ( true ( cell ?m 3 ?x ) ) ) ( <= ( column ?n ?x ) ( true ( cell 1 ?n ?x ) ) ( true ( cell 2 ?n ?x ) ) ( true ( cell 3 ?n ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 1 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 3 ?x ) ) ) ( <= ( diagonal ?x ) ( true ( cell 1 3 ?x ) ) ( true ( cell 2 2 ?x ) ) ( true ( cell 3 1 ?x ) ) ) ( <= ( line ?x ) ( row ?m ?x ) ) ( <= ( line ?x ) ( column ?m ?x ) ) ( <= ( line ?x ) ( diagonal ?x ) ) ( <= nolinex ( not ( line x ) ) ) ( <= nolineo ( not ( line o ) ) ) ( <= ( legal xplayer ( mark ?x ?y ) ) ( true ( cell ?x ?y b ) ) ) ( <= ( legal oplayer ( mark ?x ?y ) ) ( true ( cell ?x ?y b ) ) ) ( <= ( goal xplayer 50 ) ( line x ) ( line o ) ) ( <= ( goal xplayer 100 ) ( line x ) nolineo ) ( <= ( goal xplayer 0 ) nolinex ( line o ) ) ( <= ( goal xplayer 50 ) nolinex nolineo ( true ( step 7 ) ) ) ( <= ( goal oplayer 50 ) ( line x ) ( line o ) ) ( <= ( goal oplayer 100 ) nolinex ( line o ) ) ( <= ( goal oplayer 0 ) ( line x ) nolineo ) ( <= ( goal oplayer 50 ) nolinex nolineo ( true ( step 7 ) ) ) ( <= terminal ( true ( step 7 ) ) ) ( <= terminal ( line x ) ) ( <= terminal ( line o ) ) ) 30 15)';
$gdl = substr( $gdl, 1, length( $gdl ) - 2 );
print Dumper $gdl;
my $world = parse_gdl( $gdl, {} );
ok(ref $world->{body},'body is ok');
done_testing;

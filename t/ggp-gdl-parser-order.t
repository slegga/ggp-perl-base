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
    if ($^O eq 'MSWin32') {
        $homedir = 'c:\privat';
    } else {
        $homedir = abs_path($0);
        $homedir =~s|/[^/]+/[^/]+$||;
    }
}

# perldebug t/ggp-gdl-parser-order.t


use lib "$homedir/lib";

use GGP::Tools::Parser ();

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
    my $afternorows = @{$gdl->{facts}} + @{$gdl->{init}} + @{$gdl->{head}} + @{$gdl->{body}};
    is ($norows, $afternorows, 'Have the right number of rows after ordering');
    my $test =1;
    # Head test
    # FIXME
    # head is hard to test.
    # Remove comment code below and do something similar in a new test file for a finished world "object" in data format.
    #
#    my @known = grep {defined} map{$_=~/([\w\+]+)/;$1} @{$gdl->{facts}};
#    push @known,grep {defined} map{$_=~/([\w\+]+)/;$1} @{$gdl->{init}};
#    push @known,'true','not','distinct','or';
#    for my $i (0 .. $#{$gdl->{head}}) {
#        my $line = $gdl->{head}->[$i];
#        my @lwords = ($gdl->{head}->[$i] =~ /[^?]\b([\w\+]+)/g);
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
#                warn "HEAD";
#                warn "Error on word: ". $lword;
#                warn "Error on line: ". $gdl->{head}->[$i];
#                warn Dumper $gdl->{head};
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

done_testing;

package SH::Utils;
use strict;
use warnings;
use autodie;
use List::MoreUtils qw(any uniq);
use utf8;
use Exporter 'import';
our @EXPORT_OK = qw(last_x_lines make_reverse_file_iterator spellcheck);

my ($homedir,$dirsep,$dict_file);
BEGIN {
    if ($^O eq 'MSWin32') {
        $homedir = 'c:\privat';
        $dirsep = '\\';
        $dict_file = $homedir.$dirsep.'\\resource\\words.txt';
    } else {
        $homedir = $ENV{HOME};
        $dirsep = '/';
        $dict_file = '/usr/share/dict/words';
    }
}

=encoding utf8

=head1 NAME

SH::Utils  Utils that is not a part of other packages.

=head1 VERSION

0.01

=head1 SYNOPSIS

    use SH::Utils;

    #prints 10 last lines from file
    my $iterator = make_reverse_file_iterator('file');
    for (0.. 9) {
        print $iterator->();
    }

    #prints 10 last lines from file
    print join("\n",last_x_lines('filename',10));

=head1 DESCRIPTION

Container for low level functions

=head1 FUNCTIONS

=head2 make_reverse_file_iterator

Mainly an internal method. Inspired by "Higher level perl"

=cut

sub make_reverse_file_iterator {
    my ($filename) = @_;
    my ($filesize, $seekpos, $seekend, @lines,$numreads,$batchsize);
 #   my $rest='';

    open my $rfh,'<', $filename;
    $batchsize = 2048;
    $seekend = $filesize = -s $filename;
    $numreads = 0;
    return sub    {
        my $return = pop(@lines);
        if ( ! defined $return ) {
            $numreads++;
            $seekpos = $filesize - $numreads * $batchsize;
            $seekend = $seekpos + $batchsize;
            if ($seekpos < 0) {
                $seekpos = 0 ;
                seek($rfh,$seekpos, 0);
            } else {
                seek($rfh,$seekpos, 0);
                my $rest = <$rfh> if $seekend;
                $seekend -= length($rest);
            }
            my $line='x';
            while ($seekpos < $seekend && $line) {
                $line = <$rfh>;
                last if !defined $line;
                push @lines,$line;
                $seekpos += length($line);
            }
            $return = pop(@lines);
        }
        return $return;

    }

}




=head2 last_x_lines

input filename, number of lines wanted

Extract the last lines from a file
Returns an array of lines

=cut

sub last_x_lines {
    my ($filename, $lineswanted) = @_;
    my ($line, $filesize, $seekpos, $numread, @lines);

    open my $rfh,'<', $filename;

    $filesize = -s $filename;
    $seekpos = 50 * $lineswanted;
    $numread = 0;
    while ($numread < $lineswanted) {
        @lines = ();
        $numread = 0;
        my $newpos = $filesize - $seekpos;
        if ($newpos<0) {
            $newpos=0;
        }
        seek($rfh, $newpos, 0);
        <$rfh> if $seekpos < $filesize; # Discard probably fragmentary line
        while (defined($line = <$rfh>)) {
            push @lines, $line;
            shift @lines if ++$numread > $lineswanted;
        }
        if ($numread < $lineswanted) {
            # We didn't get enough lines. Double the amount of space to read from next time.
            if ($seekpos >= $filesize) {
                die "There aren't even $lineswanted lines in $filename - I got $numread\n";
            }
            $seekpos *= 2;
            $seekpos = $filesize if $seekpos >= $filesize;
        }
    }
    close $rfh;
    return @lines;
}

=head2 spellcheck

Check input scalar for English spelling errors.
 $_[0}: text to be checked as scalar
 $_[1]: additional legal words as array reference
Return a list of unkown words from the text.

TODO:
Read from .personaldictionary.txt for own words.

=cut

sub spellcheck {
    my $text = shift; #text to be spellchecked
    my $extrawords_ar = shift;#additional legal words as
    my @mywords= split(/\b/, $text);
    @mywords = sort {lc($a) cmp lc($b)} @mywords;
    @mywords = uniq @mywords;

    my @return=();

    my @ownwordlist=();
    if ($extrawords_ar) {
        @ownwordlist=@{$extrawords_ar};
    }
    my $pdfile = $homedir.$dirsep.'.personaldictionary.txt';
    if (-r $pdfile) {
        open my $pdfh,'<',$pdfile;
        my @tmp = <$pdfh>;
        push @ownwordlist, @tmp;
        close $pdfh;
        map {chomp $_} (@ownwordlist);
        warn "Empty list " if ! @ownwordlist;
    } else {
        warn "Cant find $pdfile";
    }
    my @newwords=();
    for my $word(@mywords){
        next if $word !~ /\w/;
        next if $word =~ /\d/;
        next if $word =~/\_/;
        next if $word =~ /^\w\w$/;
        next if $word =~ /^\w$/;
        next if any {$_ eq $word || $_ eq lc($word) } @ownwordlist;

        push @newwords, $word;
    }
    #print join("\n",@newwords);
#    print join(" ",@mywords);
#    my %capmywords = map {(lc $_,$_)} @newwords;
#    @newwords = map{lc} @newwords;
    @newwords = sort {$a cmp $b} @newwords;
    @newwords = uniq @newwords;
    @newwords = grep {defined $_ && $_} @newwords;

    open my $fhr,'<',$dict_file;
    my $word = shift @newwords;
    my $dword=<$fhr>;

    while (defined $dword && defined  $word) {

        if ($dword eq $word || $dword eq lc $word) {
            $word = shift @newwords;
            $dword = <$fhr>;
            chomp $dword if defined $dword;
        } elsif ( $dword lt $word) {
            if  ( $dword lt lc $word ) {
                $dword = <$fhr>;
                chomp $dword if defined $dword;
            }
        } elsif ( $dword gt $word) {
            if  ( $dword gt lc $word) {
                push @return, $word;
                $word = shift @newwords;
            } else {
                push @newwords,lc $word;
                @newwords = sort {$a cmp $b} @newwords;
                @newwords = uniq @newwords;
                $word = shift @newwords;
            }

        } else {
            die "$word dict:$dword ";
        }

        #die "No die $dword $word";
    }
    close $fhr;
    return @return;#@capmywords{@return};
}


=head1 AUTHOR



=cut

1;

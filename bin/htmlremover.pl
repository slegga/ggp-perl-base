#!/usr/bin/env perl#!/usr/bin/env perl
=head1 NAME

Mojo debug remover

=cut
use strict;
use warnings;
use Storable qw(dclone);
my $homedir;

use FindBin;
use lib "$FindBin::Bin/../lib";
use strict;
use warnings;
use Storable qw(dclone);
my $homedir;

use FindBin;
use lib "$FindBin::Bin/../lib";

#open $fh,'<','share/unwantedlines.txt';
#@unwanted = <>;
sub _remove_xmltags {
    my $in = shift;
    chomp $in;
    $in=~ s|\#\s||;
    $in=~ s|<.+?>| |g;
    $in=~s|\s+0.0.0.0||;
    $in=~s|\s+| |g;
    $in=~s|^\s+$||;

    chomp $in;
    return $in;
}
while (my $line=<>) {
    my $c = _remove_xmltags($line);
#    printf("%s\n",length $c);
    print (length $c ? "$c\n" : '' );
}

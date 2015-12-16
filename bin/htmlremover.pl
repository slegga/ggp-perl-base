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

open $fh,'<','share/unwantedlines.txt';
@unwanted = <>;

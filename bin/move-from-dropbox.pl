#!/usr/bin/env perl
use Mojo::Base -strict;
use autodie;
use File::Copy qw(copy);
use Data::Dumper;
use Git;
use File::Find;
use Path::Tiny; # http://perlmaven.com/how-to-replace-a-string-in-a-file-with-perl
my $gitdir = $ENV{HOME} . '/git/ggp-perl-base';

#
#   Check git status
#
# my $version = Git::command_oneline('version');
# my $repo = Git->repository (Directory => $gitdir);
# my @revs = $repo->command('status');
# print Dumper @revs;
# die "Unclean git: do git status;git commit" if grep {/Untracked files/} @revs;

#
#   Copy the bin catalog
#

my $bindir = $ENV{HOME} . '/bin';
my $gitbin = $gitdir.'/bin';
opendir(my $dh, $bindir) || die "can't opendir:$bindir $!";
my @ggp = grep { /ggp.*pl$/ && -f "$bindir/$_" } readdir($dh);
closedir $dh;
print Dumper @ggp;
for my $binfile(@ggp) {
    copy($bindir.'/'.$binfile, $gitbin.'/'.$binfile);
}

#
#   Copy the lib catalog
#

#system('cp -r '.$ENV{HOME} .'/lib/SH '.$gitdir.'/lib/SH') or die "Didnt work";
# Må lages mer robost prøv iterator

copy ($ENV{HOME} .'/lib/Nx/SQL/ResultSet.pm', $ENV{HOME} .'/lib/SH/ResultSet.pm');
copy ($ENV{HOME} .'/lib/Nx/SQL/Script.pm', $ENV{HOME} .'/lib/SH/Script.pm');
#
#   Remove unwanted files from git
#

# no need

#
#   Anonymousize
#
my $iter = path($gitdir)->iterator({ recurse=>1 });
while ( my $path = $iter->() ) {
    next if $path->basename !~ /\.(?:pm|pl)/;
    next if $path->stringify =~ /\.git\//;
    printf "%s\n",$path->stringify;
    my $data = $path->slurp_utf8;
    $data =~ s/Slegga/Slegga/g;
    $data =~ s/stein.hammer\@telenor\.com/slegga\@gmail\.com/g;
    $data =~ s/Nx\:\:SQL/SH/g;
    $path->spew_utf8( $data );
}

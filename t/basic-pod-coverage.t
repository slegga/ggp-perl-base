use Test::More;
use lib 'lib';
use Test::Pod::Coverage;
#plan skip_all => 'Devel::Cover' if $ENV{HARNESS_PERL_SWITCHES} and $ENV{HARNESS_PERL_SWITCHES} =~ /Devel::Cover/;
#eval 'use Test::Pod::Coverage; 1' or plan skip_all => 'Test::Pod::Coverage required';
all_pod_coverage_ok({ also_private => [ qr/^[A-Z_]+$/ ] });
done_testing;

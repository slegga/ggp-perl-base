#!/usr/bin/env perl
use strict;
use warnings;
use autodie;


use v5.12;

use Mojo::UserAgent;

=encoding utf8

=head1 NAME

ggp-con-ua.pl

=head1 DESCRIPTION

Test script for looking at HTTP request.
This script must be modified for usage.
Not complete.

=head1 USAGE

bin/ggp-client.pl
~/git/ggp-base$ ./gradlew player
bin/ggp-con-ua.pl

=cut

my $ua = Mojo::UserAgent->new;



my $base_url  = "http://127.0.01:9147";
my $agent_url = "http://127.0.01:3000";

say "########## ggp-base\n";

my $res1 = $ua->post($base_url,'( INFO )')->res;

say "Status: ".($res1->code // '__UNDEF__');
say $res1->headers->to_string;
say $res1->body;

 say "########## ggp-agent\n";
my $res2 = $ua->post($agent_url,'( INFO )')->res;

say "Status: ".($res1->code // '__UNDEF__');
say $res2->headers->to_string;
say $res2->body;

=head1 AUTHOR

Slegga

=cut


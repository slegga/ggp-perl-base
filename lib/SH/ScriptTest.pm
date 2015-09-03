package SH::ScriptTest;
use strict qw(vars );
use warnings;
use autodie;
use Carp;
# use Data::Dumper;
use IPC::Open3;    #export open3
use File::Basename qw(basename);
use Symbol qw(gensym);
use IO::File;
use YAML::Syck;
use Test::More();
use Test::Pod();
use parent qw( Test::More );
use feature qw(say);
use Pod::Simple::Text;
use SH::Script qw(readprivconfig);
use SH::Utils qw(spellcheck);
use List::MoreUtils qw(none);
use utf8;
use File::Slurp;

=encoding utf8

=head1 NAME

SH::ScriptTest - For testing script with systest.pl script

=head1 SYNOPSIS

    use SH::ScriptTest qw(no_plan);
    my $test=SH::ScriptTest->new(undef,'dev',@ARGV);

#projecthome,developmentflag,testsno to execute

$test->checkpod('/local/net/experimental/t527081/git/nx-mysql/bin/etl-nitra-data');

=head1 DESCRIPTION

For making test-script for running with systest.pl
The goal is make it easy to test script properly with not to much hassle.

systest.pl also check for untested script. Checking pod, spelling error, that mandatory headers are included in pod etc.

=head1 METHODS

=head2 new

constructor keeps order of catalogs
$_[0]=class_name
$_[1]=project home
$_[2]=development flag
$_[3..]= extras

=cut

sub new {
    my ( $class_name, $projecthome, $dev ) = ( shift, shift, shift );
    my $self = {};
    my $cfg  = readprivconfig();
    if ($projecthome) {
        $self->{projecthome} = $projecthome;
    } else {
        $self->{projecthome} = $cfg->{datacatalog} . '/systests/';
    }
    $self->{dev}             = ( $dev ? 1 : 0 );
    $self->{testnumber}      = 0;
    $self->{requiredpodtext} = $cfg->{requiredpodtext};
    my $tmptests = join( ',', map { substr( $_, 6 ) } grep( /^tests=/, @_ ) );

    if ($tmptests) {

        #        say "\$tmptests",$tmptests;
        confess "Invalid input " . $tmptests if ( $tmptests =~ /[\ a-zA-Z]/ );
        my @tmptests = split( ',', $tmptests );
        my @tests = ();
        my $tmpnumber;
        my $tmpstate;
        for my $t (@tmptests) {

            #            say $t;
            if ( $t =~ /\-/ ) {
                confess "No code for sequenze yet";
            } else {
                push @tests, $t;
            }
        }

        #        say "\@tests: " . join(',',@tests);
        $self->{tests} = \@tests;
    }

    my $picktests = join( ',', map { substr( $_, 10 ) } grep( /^picktests=/, @_ ) );
    if ( $picktests && $picktests ne 'picktests=' ) {
        my $basename = basename($0);
        for my $test ( split( ',', $picktests ) ) {
            my ( $file, $linenos ) = split ':', $test, 2;
            next if ( $file !~ /$basename/ );
            push @{ $self->{tests} }, split( /\+/, $linenos );
        }
    }
    bless( $self, $class_name );
}

=head2 ok

Call parent

=cut

sub ok {
    my $self =  shift;
    my $result =   shift;
    my $explenation = shift;
    return Test::More::ok($result, $explenation);
}

=head2 skip

Override Test::More add up test counter before calling parent skip.

=cut

sub skip {
    my $self =  shift;
    my $why =   shift;
    my $count = shift;
    $self->{testnumber} += $count;
    return Test::More::skip($why, $count);
}

=head2 pod_file_ok

Override Test::More add up test counter before calling parent pod_file_ok.

=cut


sub pod_file_ok {
    my $self = shift;
    my $podfile = shift;

    $self->{testnumber} ++;
    my $skip = $self->_skip_test;
    return $skip if $skip;

    return Test::Pod::pod_file_ok($podfile);
}

=head2 mybasename

Find basename. File::Basename does not do the job.
Return filename, and path for commando

=cut

sub mybasename {
    my $self         = shift;
    my $filepathname = shift;
    confess('No input') if !defined $filepathname;
    my $returnfile = $filepathname;
    $returnfile =~ s/.*\|//;             # remove before pipe
    $returnfile =~ s/(?:\S+\=\S+)//g;    # remove configsetting
    $returnfile =~ s/^\s+//;             # remove leading spaces
    $returnfile =~ s/\s+$//;             # remove trailing spaces
    $returnfile =~ s/\ .*//;             #remove options
    $returnfile =~ s/(.*\/)//;
    my $returndir = $1;
    $returnfile, $returndir;
}


#
#   _skip_test
#
#   Check if test should be skipped because just a subset of tests is wanted
#

sub _skip_test {
    my $self       = shift;
    if ( exists $self->{tests} ) {

        #        confess "OK: " . $self->{tests}." " . join(',',@{$self->{tests}});
        confess "Not an array ref: " . $self->{tests} if ref $self->{tests} ne 'ARRAY';
        if ( !grep( $self->{testnumber} == $_, @{ $self->{tests} } ) ) {
            confess '$parameters->{tests} has to be an array reference: ' . ( $self->{tests} // 'undef' )
                if ( ref $self->{tests} ne 'ARRAY' );

            #hopp over testen
            my $return = $self->ok( 1, 'skipping test' );
            return $return;
        }
    }
    return;
}

=head2 testscript

input 'commandline', [verify file]
check that nothing is written to STDERR.
Verify output against verify file. The verify file is meant to verify the output with regexps
parameters
    {noexec}=1 :        no execution of script.
    {stderr}:           accept writing to STDERR
    {nxsqlstderr}:      accept writing to STDERR but report err for \d\d:\d\d:\d\d\ [a-z\.]+\:\d+\>
    {nxscriptstderr}:   accept writing to STDERR but report err for (?:FATAL|ERROR)>
Return 1 for OK and 0 FOR Fail

=cut

sub testscript {
    my $self       = shift;
    my $cmd        = shift;
    my $verifyfile = shift;
    my $parameters = shift;
    croak("Not an hash ref") if ( defined $parameters && ref $parameters ne 'HASH' );
    my $return = 1;
    my $reason = 'Testing script: ' . ( $self->mybasename($cmd) )[0];
    $self->{testnumber}++;

    my $skip = $self->_skip_test;
    return $skip if $skip;

    my $verify_hr;
    my $verifydir = $self->{projecthome} . '/verify/';
    if ($verifyfile) {
        my $file = $verifydir . $verifyfile;
        open my $FH, '<', $file or die "Failed to read $file: $!$@";
        $verify_hr = YAML::Syck::Load(
            do { local $/; <$FH> }
        );    # slurp content
        if ($parameters) {
            my ( $key, $value );
            $$verify_hr{$key} = $value while ( ( $key, $value ) = each %$parameters );
        }
        @$verify_hr{ keys %$parameters } =
            values %$parameters;    # merge %$parameters into %verify_hr. %$parameters overrides %verify_hr
    }

    #     my $outputcompare = shift;
    local *CATCHOUT = IO::File->new_tmpfile;
    local *CATCHERR = IO::File->new_tmpfile;
    my $runcmd = $cmd;
    my ( $basename, $basedir ) = $self->mybasename($runcmd);
    if ( $self->{dev} && !defined $basedir || $basedir !~ /\w/ ) {
        my $devbasename;
        open( my $fh, '<', $self->{projecthome} . '/tmp/myscripts.txt' );
        while (<$fh>) {
            if (/\Q$basename\E$/) {
                $devbasename = $_;
                chomp $devbasename;
                last;
            }
        }
        close $fh;
        if ($devbasename) {
            $runcmd =~ s/\Q$basename\E/$devbasename/;
        }
    }
    if ( !defined $verify_hr || !$verify_hr->{noexec} ) {

        # Get base script name with directory if set. For getting better error messages.
        my $tmpcmd = $runcmd;
        $tmpcmd =~ s/.*\|//;
        my @basescript = split /\s+/, $tmpcmd;
        my $basescript;
        for my $scriptpart (@basescript) {

            #            print $scriptpart//'[undef]',"\n";
            next if !defined $scriptpart;
            next if !$scriptpart;
            next if ( $scriptpart =~ m/\=/ );
            $basescript = $scriptpart;
            last;
        }

        if ( !-f $basescript ) {
            $reason = ( $basescript // '[undef]' )
                . " does not exists! Control if right script name is given, that path is not given and right are ok.";
            $return = 0;
        } else {
            my $pid = open3( gensym, ">&CATCHOUT", ">&CATCHERR", $runcmd ) or confess( "Cannot open3 \'$runcmd\' " . $@ );
            waitpid( $pid, 0 );
            seek $_, 0, 0 for \*CATCHOUT, \*CATCHERR;
            my @result = <CATCHOUT>;
            my @err    = <CATCHERR>;
            if (@err) {
                if ( $verify_hr->{stderr_ok} ) {    # react on stderr
                    my @vererrok;
                    push( @vererrok, { line => $_, iserr => 1 } ) for (@err);
                    foreach my $regexp ( @{ $verify_hr->{stderr_ok} } ) {
                        @vererrok = map { { line => $_->{line}, iserr => ( $_->{line} =~ /$regexp/ ? 0 : 1 ) } } @vererrok;
                    }
                    if ( exists $verify_hr->{stderr_err} && !grep { $_->{iserr} } @vererrok ) {
                        foreach my $errregexp ( @{ $verify_hr->{stderr_err} } ) {
                            @vererrok =
                                map { { line => $_->{line}, iserr => ( $_->{line} =~ /$errregexp/ ? 1 : 0 ) } } @vererrok;
                        }
                    }
                    if ( grep { $_->{iserr} } @vererrok ) {
                        $reason =
                              ( exists $verify_hr->{name} ? $verify_hr->{name} : '' )
                            . ' write to STDERR '
                            . $cmd . ':\''
                            . join( '', map { $_->{line} } grep { $_->{iserr} } @vererrok );
                        $return = 0;
                    } else {
                        $return = 1;
                    }

                } elsif ( exists $verify_hr->{stderr_err} ) {    # do not react on stderr
                    for my $regexp ( @{$verify_hr->{stderr_err}} ) {
                        my @greperrs = grep { $_=~/$regexp/ } @err ;
                        if ( @greperrs ) {
                            $return = 0;
                            $reason .=
                                  ( exists $verify_hr->{name} ? $verify_hr->{name} : '' )
                                . " write to STDERR /"
                                . $regexp
                                . "/ \n$cmd\n"
                                . join( "\n", @greperrs ) . "\n";
                        }
                    }
                } else { # react on stderr
                    $return = 0;
                    $reason = 'Script Write to STDERR: ' . $cmd . ':\'' . join( '', @err );
                }
            }
        }
    }
    $self->ok( $return, $reason );
}

=head2 checkpod

Takes a filename and check if required headings are implemented
Look for SYNOPSIS and check that it compile.

=cut

sub checkpod {
    my $self    = shift;
    my $podfile = shift;

    $self->{testnumber}++;
    my $skip = $self->_skip_test;
    return $skip if $skip;

    my $return  = 1;                           #1=OK
    my $reason  = 'POD check - ' . $podfile;
    $Text::Wrap::columns = 1000;
    my $parser = Pod::Simple::Text->new();     #sentence => 0, width => 1000);{width => 1000}
    my $pod;


    $parser->output_string( \$pod );
    $parser->parse_file($podfile);
    my @required_headers;

    if ( $podfile =~ /\.pm$/ ) {
        @required_headers = ( 'NAME', 'SYNOPSIS', 'DESCRIPTION', '(?:METHODS|FUNCTIONS)', 'AUTHOR' );
    } else {
        @required_headers = ( 'NAME', 'DESCRIPTION', 'AUTHOR' );
    }
    my $next_h      = shift(@required_headers);
    my $sectiontext = '';
    my $sectionname = '';
    my $textbody    = '';
    if ( ref $self->{requiredpodtext} ) {
        for my $req ( @{ $self->{requiredpodtext} } ) {
            if ( $pod !~ /$req/ ) {
                $return = 0;
                $reason .= " Missing required text: $req";
            }
        }
    }
    my $slurp = read_file($podfile);
    if ( $slurp !~ /\=encoding utf8/ms ) {
        $return = 0;
        $reason .= " POD is missing '=encoding utf8'. ";
    } elsif ( !utf8::is_utf8($pod) ) {    #|| ! utf8::valid($pod)) {
        $return = 0;
        $reason .= " POD IS NOT UTF8 Try: file -ib $podfile. iconv -f xxx -t utf8 file >file.utf8";
    }

    #print quotemeta($pod)."\n";
    my @podlines = split( "\n", $pod );
    for my $line (@podlines) {
        last if !defined $next_h;
        if ( $line =~ /^\w/ ) {

            #endlast section start a new_tmpfile
            if ( $sectionname eq 'SYNOPSIS' ) {
                if ( $podfile =~ /\.pm$/ && $podfile !~ /ScriptTest/ ) {
                    my $locallib = $podfile;
                    $locallib =~ s!/lib.+!/lib!;
                    my $tmp = "no strict;use lib '$locallib';if (0) {" . $sectiontext . '}';
                    eval($tmp);
                    if ($@) {
                        warn $tmp;
                        $return = 0;
                        $reason .= ' SYNOPSIS do not compile: ' . $@;
                    }

                    #warn ()=$sectiontext=~/\;\s\S/g;
                    if (1 < (() = $sectiontext=~/\;\s\S/g)) { # more than one line synopsis with out indent
                        warn $sectiontext;
                        $return = 0;
                        $reason .= ' SYNOPSIS must start lines with whitespace to get it right.';
                    }
                }
            } elsif (
                none {
                    $sectionname eq $_;
                }
                ( 'EXAMPLES', 'TESTING', 'USE BY' )
                )
            {

                #            if ( $line !~ /^\s\s\w/) {
                $sectiontext =~ s/\'\w+\'//gm;
                $sectiontext =~ s/\"\w+\"//gm;
                $sectiontext =~ s/\{\w+\}//gm;
                $sectiontext =~ s/\[\w+\]//gm;
                $sectiontext =~ s/\<\w+\>//gm;
                $sectiontext =~ s/\$\w+//gm;
                $sectiontext =~ s!(\w+)?(\/\w+)+!!gm;
                $textbody .= $sectiontext;
            }
            $sectionname = $line;
            $sectiontext = '';
            if ( $line =~ /^$next_h$/ ) {
                $next_h = shift(@required_headers) || undef;
            }

            #        print $line."\n";
        } else {
            if ( $sectionname !~ /(?:METHODS|FUNCTIONS)/ || $line !~ /^\ \w/ ) {
                $sectiontext .= $line . "\n";
            }
        }
    }
    if ($next_h) {

        #print "$podfile: First missing or missplaced head1: ".$next_h."\n";
        $reason = "$podfile: First missing or missplaced head1: " . $next_h;
        $return = 0;
    } else {
        my @legalwords = grep {/\w/} split /\b/, $podfile;
        my @misspell = spellcheck( $textbody, \@legalwords );
        if (@misspell) {
            $return = 0;
            $reason .= ' spellcheck: misspelled words: ' . join( ', ', @misspell );
        }
    }
    $self->ok( $return, $reason );
}

=head2 check_for_no_tidy

Look for compressed coding. And suggest perltidy for script package

=cut

sub check_for_no_tidy {
    my $self     = shift;
    my $codefile = shift;

    $self->{testnumber}++;
    my $skip = $self->_skip_test;
    return $skip if $skip;

    my $return   = 1;                                 #1=OK
    my $reason   = 'Perltidy check - ' . $codefile;


    my $slurp = read_file($codefile);
    if ( $slurp =~ /^[^\#^\"\']+[^\%]\=\$/m ) {
        $return = 0;
        $reason = "Not tidy: perltidy $codefile";
    }
    $self->ok( $return, $reason );
}

=head2 finduntestedscripts

No input.
Check if data/systests/tmp/myfiles.txt contains data(except for .pm) not mentioned in data/systests/myscriptstests.txt

=cut

sub finduntestedscripts {
    my $self       = shift;
    my $myfilestxt = $self->{projecthome} . "\/tmp\/myscripts.txt";
    open( my $fh, "<", $myfilestxt ) or confess( "Cannot open file $myfilestxt for read", $@ );
    my @myscripts = grep {/^\w/} map { chomp; ( $self->mybasename($_) )[0] if ( !/(?:HEAD|\.pm)$/ ) } <$fh>;
    close $fh;
    my $testdir = $self->{projecthome} . '/*.t';
    for my $testfilename ( glob($testdir) ) {
        last if ( !@myscripts );
        open( $fh, '<', $testfilename ) or confess( "Cannot open file $testfilename for read", $@ );
        my $file = do { local $/; <$fh> };
        next if !$file;
        for ( my $i = $#myscripts; $i >= 0; $i-- ) {
            if ( $file =~ /\Q$myscripts[$i]\E/ ) {
                splice( @myscripts, $i, 1 );
            }
        }
    }

    #    local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + 1;
    $self->ok( !@myscripts, "Untested scripts:\n" . join( ', ', @myscripts ) );
}
1;

=head1 AUTHOR



=cut

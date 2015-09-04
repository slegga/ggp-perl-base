package SH::Script;
use Getopt::Long::Descriptive qw(prog_name describe_options prog_name);
use Term::ANSIColor qw(:constants);
use Pod::Text::Termcap;
use strict;
use warnings;
use autodie;
use Carp;
use List::MoreUtils q(any);
use Term::ReadKey;
use Exporter 'import';
use YAML::Syck ();
our @EXPORT_OK = qw(options_and_usage usage debug ask readprivconfig);
my ($homedir,$dirsep);
BEGIN {
    if ($^O eq 'MSWin32') {
        $homedir = 'c:\privat';
        $dirsep = '\\';
    } else {
        $homedir = $ENV{HOME};
        $dirsep = '/';
    }
}

=encoding utf8

=head1 NAME

SH::Script - A part of Sleggas personal developer suite

=head1 SYNOPSIS

    use SH::Script;
    use Data::Dumper;
    my @ARGV_COPY = @ARGV;
    my ( $opts, $usage, $argv ) =
        options_and_usage( $0, \@ARGV, "%c %o",
        [ 'from|f=s', 'from emailadress' ],
        [ 'subject|s=s', 'Email Subject. Also used to find the to address if not supported',],
        [ 'info', 'Print out schema for where to send emails' ],
    );

    print Dumper $opts;
    usage();

=head1 DESCRIPTION

The main method is options_and_usage
Make it easy to document input parameters. And script --help will show
all form of documentation.

=head2 Reason for this module

I like to debug.
Anonymous subroutines can not be debugged in the tools I have seen so far.

=head1 FUNCTIONS

=head2 options_and_usage

args: podfile \@ARGV, $usage_desc, @option_spec, \%arg
podfile:        usually $0
\@ARGV:         input from shell
$usage_desc:    "%c %o"
@option_spec:   array of array ref. Inner array: ["option|flag", "option description", options]
\%arg:          input for describe_options method, in addition to return_uncatched_arguments => 1 for leaving unhandled arguments in @ARGV

Input types: s=string i=integer, none=Boolean

This method is a overbuilding og Getopt::Long::Descriptive. Check for options not read. Remove error message when putting an --help when there is a required option.

=cut

my ($opts, $usage);
my %answer_defaults=();
sub options_and_usage {
    #my @ARGV_COPY = @ARGV;
    my ($podfile,$argv_ar,$usage_desc, @opt_spec_ar )= @_;
    my $arg_hr;
    if (ref $opt_spec_ar[-1] eq 'HASH') {
        $arg_hr=pop(@opt_spec_ar);
    }
    @ARGV=@$argv_ar;
    # add missing options if help is one of the arguments
    if (grep /^--(help|h)$/,@ARGV) {
        for my $op(@opt_spec_ar) {
            if (exists ${$$op[2]}{required} && ${$$op[2]}{required}) {
                die "No match ".$$op[0] if ($$op[0]!~/^(\w+)/);
                my $dummyopt='--'.$1;
                $dummyopt.='="0"' if ($$op[0]=~/\=/);
                push (@ARGV,$dummyopt);
            }
        }
    }
    # if ! grep
    push (@opt_spec_ar,
    [ 'dry-run!',          'print dbchanges instead of doing them',                                { default  => 0 } ],
    [ 'log-level=s',       'Set loglevel. Valid values: trace, debug, info, warn, error, fatal' ],
    [ 'help|man',         'This text' ],
#    [ 'noinfoscreen',     'Do not print info messages to screen (batchmode)' ],
    );
    my $uncatched_arguments_ar=undef;
    my $unc_arg_flag=0;
    if (defined $arg_hr && exists $arg_hr->{'return_uncatched_arguments'} && $arg_hr->{'return_uncatched_arguments'}) {
        delete $arg_hr->{'return_uncatched_arguments'};
        $unc_arg_flag=1;
    }
    ( $opts, $usage ) = describe_options($usage_desc, @opt_spec_ar, $arg_hr) or &usage();
    usage($podfile,1) if ( $opts->help );
    if (@ARGV) {
        if ($unc_arg_flag) {
            $uncatched_arguments_ar=\@ARGV;
        } else { #not expected extra args
            printf STDERR "Uncatched arguments: %s\n", join( ', ', @ARGV ),"\n";
            usage();
        }
    }
    return $opts,$usage,$uncatched_arguments_ar;
}

=head2 usage

args: $podfile, verboseflag
Print out help message and exit.
If verbose flag is on then print the pod also.

=cut

sub usage {
    my $podfile=shift;
    my $verbose=shift;
    print BOLD $usage->text;
    exit if (!$verbose || !$podfile);
    my $parser=Pod::Text::Termcap->new(sentence => 0, width => 80 );
    $parser->parse_from_filehandle($podfile);
    exit;
}

=head2 debug

primitive logging for logging before SH::X is loaded
Takes one or more messages, and print if log-level is trace or debug

=cut

sub debug {
    my @message = @_;
    print( @message, "\n" ) if exists $opts->{log_level} && $opts->{log_level} =~ /^(?:trace|debug)$/;
}

=head2 ask

 question = text
 choices_ar = choices_ar or a qr regexp
 {
   exit_on_nochoice 0 = repeat till ok answer, 1 = stop script, 2 = continue
   forced_answer    The answer when force flag is set.
   is_forced        0=wait for user, 1=computer choose, 2=comp choose and quiet
   remember =       [0|1] remember last answer and set this to default
   secret           [0|1] no show stdin to shell
 }

Ask user questions like Are you sure? or What is your favorite color?
Input is STDIN

=cut

sub ask {
    my $question = shift;
    my $choices_ar = shift;
    my $options_hr = shift;
    my $default;
    if (ref $options_hr eq 'HASH'){
        if (exists $options_hr->{forced_answer}) {
            $default = $options_hr->{forced_answer};
        } elsif ( $options_hr->{'remember'} && exists $answer_defaults{$question}) {
            $default = $answer_defaults{$question};
        }
    }
    confess "Argument spare @_" if @_;
    my $answer;
        if (! defined $choices_ar and ! defined $options_hr) {
            # Typically Press any key to continue questions
            print $question;
            ReadMode 4; # Turn off controls keys
            while (not defined ($answer = ReadKey(-1))) {
                    # No key yet
            }
            #print "Get key $key\n";
            ReadMode 0; # Reset tty mode before exiting
            print "\n";
        } elsif ( defined $choices_ar ) {
            while (1) {
                #Print question
                if (! defined $options_hr ||! exists $options_hr->{is_forced} ||!defined $options_hr->{is_forced} ||! $options_hr->{is_forced} == 2) {
                    print "$question ";
                    if (ref $choices_ar eq 'ARRAY') {
                        print "(".join(',',@$choices_ar).")";
                    } else {
                        print $choices_ar;
                    }
                    if ($default) {
                        print '['.$default.']';
                    }
                    print "? ";
                }
                #user in control
                if (! defined $options_hr || ! exists $options_hr->{is_forced} || ! $options_hr->{is_forced} ) {
                    # print "$question ";
                    $answer = _ask_stdin($options_hr->{secret});
                    my @dummy;
                    if ( $choices_ar =~ /^\(\?/ ) {
                        if (lc($answer) =~ /^$choices_ar$/) {
                            last;
                        }
                    } else {
                        @dummy = grep({lc($answer) eq lc($_)} @$choices_ar);
                    }
    #                print "dummy[0]:".$dummy[0],"\n" if @dummy;
                    if (! @dummy ) {
                        if (defined $options_hr && exists $options_hr->{exit_on_nochoice} && $options_hr->{exit_on_nochoice} == 1){
                            croak("Execution stopped by user.")
                        } elsif ($default && !$answer) {
                            $answer = $default;
                            last;
                        } elsif (($options_hr->{exit_on_nochoice}//0) == 2) {
                            $answer = undef;
                            last;
                        }
                    } else {
                        last;
                    }
                #computer in control
                } else {
                    if (!($options_hr->{exit_on_nochoice} && ! $options_hr->{forced_answer} ) && ! any {$default eq $_} grep {defined }@$choices_ar) {
                        confess "Forced answer is not in the valid answer list: $options_hr->{forced_answer}, (".join(',',@$choices_ar).")\n";
                    }
                    if ($options_hr->{is_forced} != 2) {
                        print $default,"\n";
                    }
                    $answer = $default;
                    last;
                }
            }
        } else {
            confess "Must either have choices and options or none";
        }
    if ($options_hr->{'remember'}) {
        $answer_defaults{$question} = $answer;
    }
    return $answer;
}

sub _ask_stdin {
    my $hidden_f =shift;
    my $return;
    if ($hidden_f) {
        ReadMode('noecho'); # don't echo
    }
    $return = <STDIN>;
    if ($hidden_f) {
        ReadMode(0); # back to normal
        print "\n";
    }
    chomp ($return);
    return $return;
}

=head2 readprivconfig

Return a hash object for the users .nxsqlscript.yml located in users home catalog. Method created because ease moving all perl script to nx-mysql/script from none git administrated catalogs.

Takes no input.

=cut

sub readprivconfig {

    confess "No HOME catalog detected!" if ! $homedir;
    confess "Cant find home catalog $homedir" if ! -d $homedir;
    my $cfile = $homedir.$dirsep.'.nxsqlscript.yml';
    confess "Cant find or read the file $cfile" if (! -r $cfile);
    open my $FH, '<', $cfile or die "Failed to read $cfile: $!";
    return YAML::Syck::Load(do { local $/; <$FH> }); # slurp content
}


=head1 AUTHOR

Slegga - C<slegga@gmail.com>

=cut

1;

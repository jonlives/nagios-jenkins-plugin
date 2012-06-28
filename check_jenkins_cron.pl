#!/usr/bin/perl -w

# Check for periodic Jenkins jobs which have not run successfully.
#
# A re-written from scratch version of check_jenkins_job_extended.pl, focusing on jobs which are meant
# to be run periodically. This is designed to alert if there have been no successful builds within a
# timeframe, not just if a build has been failing for a duration. See usage output for options.
#
# 2012 Nick Robinson-Wall, Mendeley Ltd.

use strict;
use LWP;
use JSON; # deb: libjson-perl
use DateTime; # deb: libdatetime-perl
use URI::Escape;
use Getopt::Std;

my $rcode = "UNKNOWN";
my $response = "Couldn't determine state of job";

my $jobname;
my $jobnameU; # URL Encoded job name
my $jenkins_ubase;
my $username;
my $password;
my $thresh_warn;
my $thresh_crit;
my $alert_on_fail;
my $debug = 0;

sub main {
    # Getopts:
    # j: Job name
    # l: Jenkins URL
    # u: User (optional)
    # p: Password (optional)
    # w: Warning threshold
    # c: critical threshold
    # f: Alert on fail outside timeframe (optional)
    # v: verbosity / debug (optional)
    my %opts;
    getopts('j:l:u:p:w:c:fv', \%opts);

    if (!$opts{j} || !$opts{l}) {
        print STDERR "Missing option(s)\n\n";
        &usage;
    }
    $debug = $opts{v};    
    $jobname = $opts{j};
    $jobnameU = uri_escape($opts{j});
    $jenkins_ubase = $opts{l};
	# Remove trailing slash in URL as a path will be appended
    $jenkins_ubase =~ s,/$,,;
	# Assume http:// if not specified
    $jenkins_ubase = "http://$jenkins_ubase" if($jenkins_ubase !~ m,^https?://,);
    print STDERR "Using Jenkins base URL: $jenkins_ubase\n" if $debug;
    $username = $opts{u};
    $password = $opts{p};
    $thresh_warn = int($opts{w});
    $thresh_crit = int($opts{c});
    $alert_on_fail = $opts{f};
    
    if ($thresh_warn == 0 && $thresh_crit == 0) {
        print STDERR "Must set either warning or critical threshold to a sensible value\n\n";
        &usage;
    }
    
    my ($lb_status, $lb_resp, $lb_data) = apireq('lastBuild');
    my ($ls_status, $ls_resp, $ls_data) = apireq('lastStableBuild');
    my $ls_not_lb = 0;
    
    if ($ls_status || $lb_status) {
		# At least one of the API calls succeeded
        $ls_not_lb = 1 if ($ls_data->{number} != $lb_data->{number});
        my $dur_sec;
        my $dur_human;
        if ($ls_status) {
            ($dur_sec, $dur_human) = calcdur(int($ls_data->{timestamp} / 1000));
            if ($dur_sec >= $thresh_crit && $thresh_crit) {
                response("CRITICAL", "'$jobname' has not run successfully for $dur_human. " . ($ls_not_lb ? "Runs since failed. " : "No runs since. ") . $lb_data->{url} );
            } elsif ($dur_sec >= $thresh_warn && $thresh_warn && $ls_not_lb) {
                response("CRITICAL", "'$jobname' has not run successfully for $dur_human. Runs since failed. " . $lb_data->{url});
            } elsif ($dur_sec >= $thresh_warn && $thresh_warn) {
                response("WARNING", "'$jobname' has not run successfully for $dur_human. No runs since. " . $lb_data->{url})
            }
            
            if ($ls_data->{number} != $lb_data->{number} && $alert_on_fail) {
                ($dur_sec, $dur_human) = calcdur(int($lb_data->{timestamp} / 1000));
                response ( "WARNING", "'$jobname' failed $dur_human ago. " . $lb_data->{url} );
            } else {
                response ( "OK", "'$jobname' succeeded $dur_human ago. " . $lb_data->{url} );
            }
        } else {
            ($dur_sec, $dur_human) = calcdur(int($lb_data->{timestamp} / 1000));
            response ( 2, "'$jobname' has never run successfully. Last build was $dur_human ago." )
        }
    } else {
        response( "UNKNOWN", "Unable to retrieve data from Jenkins API: " . $ls_resp );
    }
    
    response($rcode, $response);
    
} # end sub main

# Calculate duration between unix epoch and now, using two methods to get the
# absolulte number of seconds between, and the human readable format.
sub calcdur($) {
    my $epoch = shift;
    my $timethen = DateTime->from_epoch( epoch => $epoch );
    my $timenow = DateTime->now;
    my $absdur = $timenow->subtract_datetime_absolute($timethen);
    my $dur = $timenow - $timethen;
    my $humandur = humanduration($dur);
    return ($absdur->seconds, $humandur);
}

# Perform Jenkins JSON API request for $_ API call (lastBuild/lastStableBuild/lastSuccessfulBuild/lastFailedBuild etc)
sub apireq($) {
    my $job = shift;
    my $url = "$jenkins_ubase/job/$jobnameU/$job/api/json";
    print STDERR "Preparing API URL for query: $url\n" if $debug;
    
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new( GET => $url );
    
    if ( $username && $password ) {
        print STDERR "Attempting HTTP basic auth as user: $username\n" if $debug;
        $req->authorization_basic($username,$password);
    } else {
        print STDERR "Skipping authentication, username and password not specified\n" if $debug;
    }
    
    my $res = $ua->request($req);
    
    if (!$res->is_success) {
        print STDERR "Request successful. Body:\n\n" . $res->content . "\n\n" if $debug;
        return ($res->is_success, $res->status_line, undef);
     } else {
        my $json = new JSON;
        my $jobj = $json->decode( $res->content );
        return ($res->is_success, $res->status_line, $jobj);
    }
}

# Produce a string like '2w 4d 7h 0m 12s' for the given DateTime::Duration object.
# Removes unneccessary units (e.g. won't display 0y 0mo when there are no years/months in the duration).
# NIH because DateTime::Format::Human::Duration won't compile, and there isn't a debian package for it.
sub humanduration($) {
    my $dur = shift;
    my $res = "";
    my $zeroc = 0;
    if ($dur->years > 0 ) {
        $res .= sprintf "%dy ", $dur->years;
        $zeroc = 1;
    }
    if ($dur->months > 0 || $zeroc) {
        $res .= sprintf "%dmo ", $dur->months;
        $zeroc = 1;
    }
    if ($dur->weeks > 0 || $zeroc) {
        $res .= sprintf "%dw ", $dur->weeks;
        $zeroc = 1;
    }
    if ($dur->days > 0 || $zeroc) {
        $res .= sprintf "%dd ", $dur->days;
        $zeroc = 1;
    }
    if ($dur->hours > 0 || $zeroc) {
        $res .= sprintf "%dh ", $dur->hours;
        $zeroc = 1;
    }
    if ($dur->minutes > 0 || $zeroc) {
        $res .= sprintf "%dm ", $dur->minutes;
        $zeroc = 1;
    }
    $res .= sprintf "%ds", $dur->seconds;
    return $res;
}

# Exit with appropriate return code for nagios OK/WARNING/CRITICAL/UNKNOWN
sub response($$) {
    my ($code, $retstr) = @_;
	my %codemap = (
        OK       => 0,
		WARNING  => 1,
		CRITICAL => 2,
		UNKNOWN  => 3
    );
	
    print "$code - $retstr";
    exit $codemap{$code};
}

sub usage {
    print << "EOF";
usage: $0 -j <job> -l <url> -w <threshold> -c <threshold> [-f] [-u username -p password] [-v]
    
    Required arguments
        -j <job>        : Jenkins job name
                          The name of the job to examine.
                          
        -l <url>        : Jenkins URL
                          Protocol assumed to be http if none specified.
                          
        -w <threshold>  : Warning Threshold (seconds)
                          WARNING when the last successful run was over <threshold> seconds ago.
                          CRITICAL when last successful run was over <threshold> and failures
                          have occured since then.
                          
        -c <threshold>  : Critical Threshold (seconds)
                          CRITICAL when the last successful run was over <threshold> seconds ago.
                           
    Optional arugments
        -f              : WARNING when the last run was not successful, even if the last
                          successful run is within the -w and -c thresholds.
                          
        -u <username>   : Jenkins Username if anonymous API access is not available
        
        -p <password>   : Jenkins Password if anonymous API access is not available
        
        -v              : Increased verbosity.
                          This will confuse nagios, and should only be used for debug purposes
                          when testing this plugin.
EOF
    exit 3;
}

&main;

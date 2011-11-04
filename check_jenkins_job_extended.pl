#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use JSON;
use DateTime;

#
# Check Hudson job status using the JSON API
#
# (c) 2011 Jon Cowie, Etsy Inc
#
# Plugin for checking hudson build that alerts when more than x builds have failed, or a build took more than y seconds.
#
# Usage:  check_jenkins_job_extended url jobname concurrentFailsThreshold concurrentUnstableThreshold buildDurationThresholdMilliseconds lastStableBuildThresholdInMinutesWarn lastStableBuildThresholdInMinutesCrit

# Nagios return values
# OK = 0
# WARNING = 1
# CRITICAL = 2
# UNKNOWN = 3

my $retStr = "Unknown - plugin error";
my @alertStrs = ("OK", "WARNING", "CRITICAL", "UNKNOWN");
my $exitCode = 3;
my $numArgs = $#ARGV + 1;

# check arguments
if ( $numArgs != 7 ) {
  print "Usage: check_jenkins_job url jobname concurrentFailsThreshold concurrentUnstableThreshold buildDurationThresholdMilliseconds lastStableBuildThresholdInMinutesWarn lastStableBuildThresholdInMinutesCrit\n";
  exit $exitCode;
}

my $jobName = $ARGV[1];
my $jobstatusURL = $ARGV[0] . "/job/" . $ARGV[1] . "/api/json";
my $failureThreshold = $ARGV[2];
my $unstableThreshold = $ARGV[3];
my $buildDurThreshold = $ARGV[4];
my $lsbThresholdWarn = $ARGV[5];
my $lsbThresholdCrit = $ARGV[6];

my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new( GET => $jobstatusURL );

my $lastBuild = "";
my $lastBuildURL = "";
my $lastStableBuild = "";
my $lastStableBuildURL = "";
my $currenttime = time;
my $buildTimeStamp = 0;
my $currentlyBuilding = "";
my $numFailedBuilds = 0;
my $numUnstableBuilds = 0;

# make request to Hudson
my $res = $ua->request($req);

# if we have a HTTP 200 OK response
if ( $res->is_success ) {
  my $json = new JSON;

  # get content
  my $obj = $json->decode( $res->content );

  $exitCode = 0;

  my $buildname = $obj->{name};
  my $lastFailedBuild = $obj->{lastFailedBuild}->{number};
  my $lastUnstableBuild = $obj->{lastUnstableBuild}->{number};
  $lastStableBuild = $obj->{lastStableBuild}->{number};
  $lastBuild = $obj->{lastBuild}->{number};
  $lastBuildURL = $obj->{lastBuild}->{url} . "/api/json";
  
  $lastStableBuildURL = $obj->{lastStableBuild}->{url};
  
  # Figure out the number of failed builds, and alert if needed
  if ( $lastFailedBuild != "" ) {
      $numFailedBuilds = $lastFailedBuild - $lastStableBuild;
  }
  
  if ( $numFailedBuilds < 0 ) {
      $numFailedBuilds = 0;
  }
  
  if ( $numFailedBuilds >= $failureThreshold && $failureThreshold != "0" ) {
      $retStr = "FailedBuilds: " . $numFailedBuilds . " (last Stable build: " . $lastStableBuild . ")";
      $exitCode = 2;
  }
  elsif ( $numFailedBuilds > 0 && $numFailedBuilds >= $failureThreshold - 2 && $failureThreshold != "0") {
      $retStr = "FailedBuilds: " . $numFailedBuilds . " (last Stable build: " . $lastStableBuild . ")";
      $exitCode = 1;
  }
  else {
      $retStr = $numFailedBuilds . " failed builds (last Stable build: " . $lastStableBuild . ")";
  }
  
  
  # Figure out the number of unstable builds, and alert if needed
  if ( $lastUnstableBuild != "" ) {
      $numUnstableBuilds = $lastUnstableBuild - $lastStableBuild;
  }
  
  if ( $numUnstableBuilds < 0 ) {
      $numUnstableBuilds = 0;
  }
  
  if ( $numUnstableBuilds >= $unstableThreshold && $unstableThreshold != "0" ) {
      $retStr = "UnstableBuilds: " . $numUnstableBuilds . " (last Stable build: " . $lastStableBuild . ")";
      $exitCode = 2;
  }
  elsif ( $numUnstableBuilds > 0 && $numUnstableBuilds >= $unstableThreshold - 2 && $unstableThreshold != "0") {
      $retStr = "UnstableBuilds: " . $numUnstableBuilds . " (last Stable build: " . $lastStableBuild . ")";
      $exitCode = 1;
  }
  else {
      $retStr = $retStr . ", " . $numUnstableBuilds . " unstable builds (last Stable build: " . $lastStableBuild . ")";
  }
  
}
else {
    $retStr = $res->{status_line};
    $exitCode = 1;
}

#Calculate build duration, and alert if needed
my $ua2 = LWP::UserAgent->new;
my $req2 = HTTP::Request->new( GET => $lastBuildURL );
my $res2 = $ua2->request($req2);
$currentlyBuilding = "";

if ( $res2->is_success ) {
    my $json2 = new JSON;
    my $obj2 = $json2->decode( $res2->content );
    my $buildDuration = $obj2->{duration};
    $currentlyBuilding = $obj2->{building};

    if ( $buildDurThreshold <= $buildDuration && $buildDurThreshold != "0" ) {
        $retStr = "Duration of last build (" . $lastBuild . "): " . $buildDuration;
        $exitCode = 2;
    }
    else {
        $retStr = $retStr . ", duration of build ". $lastBuild . " was " . $buildDuration . " millisecs";
    }
    
}
else {
    $retStr = $res2->{status_line};
    $exitCode = 1;
    $currentlyBuilding = 'false';
}

#Calculate time since last successful build

if( $numFailedBuilds > 0 || $numUnstableBuilds > 0 ) {
    if ( $lastStableBuildURL ne ""  ){
        $lastStableBuildURL = $lastStableBuildURL . "api/json";
        my $ua3 = LWP::UserAgent->new;
        my $req3 = HTTP::Request->new( GET => $lastStableBuildURL );
        my $res3 = $ua3->request($req3);
        
        if ( $res3->is_success ) {
            my $json3 = new JSON;
            my $obj3 = $json3->decode( $res3->content );
            $buildTimeStamp = $obj3->{timestamp} / 1000;
            
            my $dt = DateTime->from_epoch( epoch => $currenttime );
            my $bts = DateTime->from_epoch( epoch => $buildTimeStamp );
            my $tdiff = $dt - $bts;
            my $tmin = ($tdiff->hours * 60) + $tdiff->minutes;
            if( $currentlyBuilding eq 'false' ) {
 
               if ( int($lsbThresholdCrit) <= int($tmin) && int($lsbThresholdCrit) != "0"  && 
                     $lastStableBuild ne $lastBuild ) {
                    $retStr = "Mins since last Stable Build (" . $lastStableBuild . "): " . $tmin;
                    $exitCode = 2;
                } elsif ( int($lsbThresholdWarn) <= int($tmin) && int($lsbThresholdWarn) != "0" && 
                          $lastStableBuild ne $lastBuild ) {
                    $retStr = "Mins since last Stable Build (" . $lastStableBuild . "): " . $tmin;
                    $exitCode = 1;
                } else {
                    $retStr = $retStr . ", last Stable build (" . $lastStableBuild . ") was " . $tmin . " mins ago";
                }
            } # END if(!$currentlyBuilding)
                
        } else {
            $retStr = $res3->{status_line};
            $exitCode = 1;
        }
    }
}
    
print $alertStrs[$exitCode] . " - $retStr\n";
exit $exitCode;

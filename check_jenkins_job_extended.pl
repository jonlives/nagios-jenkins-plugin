#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use JSON;
use DateTime;
use URI::Escape;

#
# Check Hudson job status using the JSON API
#
# (c) 2011 Jon Cowie, Etsy Inc
#
# Plugin for checking hudson build that alerts when more than x builds have failed, or a build took more than y seconds.
#
# Usage: check_jenkins_job url [user_name password] job_name concurrent_fails_threshold build_duration_threshold_milliseconds last_stable_build_threshold_minutes_warn last_stable_build_threshold_minutes_crit

# Nagios return values
# OK = 0
# WARNING = 1
# CRITICAL = 2
# UNKNOWN = 3

my $retStr = "Unknown - plugin error";
my @alertStrs = ("OK", "WARNING", "CRITICAL", "UNKNOWN");
my $exitCode = 3;
my $numArgs = $#ARGV + 1;

my $ciMasterUrl;
my $jobName;

my $userName;
my $password;

my $failureThreshold;
my $buildDurThreshold;
my $lsbThresholdWarn;
my $lsbThresholdCrit;

if ( $numArgs == 8 ){
   $ciMasterUrl = $ARGV[0];
   $userName = $ARGV[1];
   $password = $ARGV[2];
   $jobName = $ARGV[3];
   $failureThreshold = $ARGV[4];
   $buildDurThreshold = $ARGV[5];
   $lsbThresholdWarn = $ARGV[6];
   $lsbThresholdCrit = $ARGV[7];
} elsif ( $numArgs == 6 ){
   $ciMasterUrl = $ARGV[0];
   $jobName = $ARGV[1];
   $failureThreshold = $ARGV[2];
   $buildDurThreshold = $ARGV[3];
   $lsbThresholdWarn = $ARGV[4];
   $lsbThresholdCrit = $ARGV[5];
} else {
  print "\nUsage: check_jenkins_job url [user_name password] job_name concurrent_fails_threshold build_duration_threshold_seconds last_stable_build_threshold_seconds_warn last_stable_build_threshold_seconds_crit\n";
  exit $exitCode;
}

my $jobStatusUrlPrefix = $ciMasterUrl . "/job/" . uri_escape($jobName);
my $jobStatusURL = $jobStatusUrlPrefix . "/api/json";

my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new( GET => $jobStatusURL );

my $lastBuild = "";
my $lastBuildURL = "";
my $lastStableBuild = "";
my $lastStableBuildURL = "";
my $currenttime = time;
my $buildTimeStamp = 0;
my $currentlyBuilding = "";
my $numFailedBuilds = 0;

if ( !$userName eq '') {
    $req->authorization_basic( $userName, $password );
}
# make request to Hudson
my $res = $ua->request($req);

# if we have a HTTP 200 OK response
if ( $res->is_success ) {
  my $json = new JSON;

  # get content
  my $obj = $json->decode( $res->content );

  $exitCode = 0;

  my $buildname = $obj->{name};
  my $lastUnsuccessfulBuild = $obj->{lastUnsuccessfulBuild}->{number};
  $lastBuild = $obj->{lastBuild}->{number};
  $lastBuildURL = $obj->{lastBuild}->{url} . "/api/json";
  $lastStableBuild = $obj->{lastStableBuild}->{number};
  $lastStableBuildURL = $obj->{lastStableBuild}->{url};

  # Figure out the number of unsuccessful builds (failed/unstable/aborted), and alert if needed
  if ( $lastUnsuccessfulBuild != "" ) {
      $numFailedBuilds = $lastUnsuccessfulBuild - $lastStableBuild;
  }
  
  if ( $numFailedBuilds < 0 ) {
      $numFailedBuilds = 0;
  }
  
  if ( $numFailedBuilds >= $failureThreshold && $failureThreshold != "0" ) {
      $retStr = "FailedBuilds: " . $numFailedBuilds . " (last Stable build: " . $lastStableBuild . ")";
      $exitCode = 2;
  } elsif ( $numFailedBuilds > 0 && $numFailedBuilds >= $failureThreshold - 2 && $failureThreshold != "0") {
      $retStr = "FailedBuilds: " . $numFailedBuilds . " (last Stable build: " . $lastStableBuild . ")";
      $exitCode = 1;
  } else {
      $retStr = $numFailedBuilds . " failed builds (last Stable build: " . $lastStableBuild . ")";
  }
  
} else {
    $retStr = "Failed retrieving status for job $jobName via API (API status line: $res->{status_line})";
    $exitCode = 3;
}

#Calculate build duration, and alert if needed
my $ua2 = LWP::UserAgent->new;
my $req2 = HTTP::Request->new( GET => $lastBuildURL );
if ( !$userName eq '' ) {
    $req2->authorization_basic( $userName, $password);
}
my $res2 = $ua2->request($req2);
$currentlyBuilding = "";

if ( $res2->is_success ) {
    my $json2 = new JSON;
    my $obj2 = $json2->decode( $res2->content );
    my $buildDuration = $obj2->{duration};
    my $buildDurationSecs = $buildDuration / 1000;
    my $buildDurationSecsAsStr = sprintf("%d", $buildDurationSecs);
    $currentlyBuilding = $obj2->{building};

    if ( $buildDurThreshold <= $buildDurationSecs && $buildDurThreshold != "0" ) {
        $retStr = "Duration of last build (" . $lastBuild . "): " . $buildDurationSecsAsStr . " seconds";
        $exitCode = 2;
    } else {
        $retStr = $retStr . ", duration of build ". $lastBuild . " was " . $buildDurationSecsAsStr . " seconds";
    }
    
} else {
    $retStr = "Failed retrieving status for last build via API (API status line: $res2->{status_line})";
    $exitCode = 3;
    $currentlyBuilding = 'false';
}

#Calculate time since last successful build


# GAH - A short comment on the logic below. This check should say "How long has it been since the first
#       broken build?" However, that requires that we look at the time of the first *failed* build, not
#       the last stable build. If we look at the last stable build, and that build happen at some
#       arbitrary time in the past, then this alert would trigger immediately (which is not desired).
#       To do this, we add 1 to the lastStableBuild to get the ID of the first unsuccessful build,
#       and we measure elapsed time relative to that build.
if( $numFailedBuilds > 0 ) {
    
  # GAH - Have to manually construct the build URL for the first failed build
  # based on the ID of the last stable build.
  my $firstFailedBuildId = ++$lastStableBuild;
  my $firstFailedBuildURL = $jobStatusUrlPrefix . "/" . $firstFailedBuildId;
  my $firstFailedBuildApiURL = $firstFailedBuildURL . "/api/json";

  if ( $firstFailedBuildApiURL ne "" ) {
    my $ua3 = LWP::UserAgent->new;
    my $req3 = HTTP::Request->new( GET => $firstFailedBuildApiURL );
    if ( !$userName eq '' ) {
      $req3->authorization_basic( $userName, $password);
    }
    my $res3 = $ua3->request($req3);
    
    while ($res3->code == "404" && $firstFailedBuildId < $lastStableBuild + $numFailedBuilds)
    {
      ++$firstFailedBuildId;
      $firstFailedBuildURL = $jobStatusUrlPrefix . "/" . $firstFailedBuildId;
      $firstFailedBuildApiURL = $firstFailedBuildURL . "/api/json";
      $req3 = HTTP::Request->new( GET => $firstFailedBuildApiURL );
      if ( !$userName eq '' ) {
        $req3->authorization_basic( $userName, $password);
      }
      $res3 = $ua3->request($req3);
    }

    if ( $res3->is_success ) {
      my $json3 = new JSON;
      my $obj3 = $json3->decode( $res3->content );
      $buildTimeStamp = $obj3->{timestamp} / 1000;
            
      my $dt = DateTime->from_epoch( epoch => $currenttime );
      my $bts = DateTime->from_epoch( epoch => $buildTimeStamp );
      my $tdiff = $bts->delta_ms($dt);
      my $tsec = ($tdiff->in_units('minutes') * 60) + $tdiff->in_units('seconds');
      if( $currentlyBuilding eq 'false' ) {
 
        if( int($lsbThresholdCrit) <= int($tsec) && int($lsbThresholdCrit) != "0" ) {
          $retStr = "Build has been broken for " . $tsec ." seconds; first failed build number: " . $firstFailedBuildId . " (" . $firstFailedBuildURL . ")";
          $exitCode = 2;
        } elsif( int($lsbThresholdWarn) <= int($tsec) && int($lsbThresholdWarn) != "0" ) {
          $retStr = "Build has been broken for " . $tsec ." seconds; first failed build number: " . $firstFailedBuildId . " (" . $firstFailedBuildURL . ")";
          $exitCode = 1;
        } else {
          $retStr .= ", build has been broken for " . $tsec ." seconds; first failed build number: " . $firstFailedBuildId . " (" . $firstFailedBuildURL . ")";
        }
      } # END if(!$currentlyBuilding)
                
    } else {
      $retStr = "Failed retrieving status for first broken build via API (API status line: $res3->{status_line})";
      $exitCode = 3;
    }
  }
}
    
print $alertStrs[$exitCode] . " - $retStr\n";
exit $exitCode;

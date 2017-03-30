#!/usr/bin/perl
# A nagios plugin for checking all jobs in specified Jenkins view
#
# (c) 2017 Piotr Chromiec @ RTBHouse com

use strict;
use LWP::UserAgent;
use JSON;
use DateTime;
use URI::Escape;

my $dayMilliseconds = 24*3600*1000;
my $retStr = "Unknown - plugin error";
my $perfData = "dummy=0";
my @alertStrs = ("OK", "WARNING", "CRITICAL", "UNKNOWN");
my $exitCode = 3;
my $numArgs = $#ARGV + 1;

my $ciMasterUrl;
my $viewName;

my $userName;
my $password;
my $criticalDaysAgo;
my $warningDaysAgo;

if ( $numArgs == 6 ){
  $ciMasterUrl = $ARGV[0];
  $userName = $ARGV[1];
  $password = $ARGV[2];
  $viewName = $ARGV[3];
  $criticalDaysAgo = $ARGV[4];
  $warningDaysAgo = $ARGV[5];
} else {
  print "
  A nagios plugin for checking all jobs in specified Jenkins view.

  It returns status as worst (highest) job status within the view.
  When job was last succesfully built:
   - more than critical_days_ago then its status is CRITICAL
   - else if more than warning_days_ago - WARNING
   - else - OK

  Produces descriptive output with Nagios performance data.

  Usage: check_jenkins_view_last_success.pl url user_name password view_name critical_days_ago warning_days_ago\n";
  exit $exitCode;
}

my $viewStatusURL = $ciMasterUrl . "/view/" . uri_escape($viewName) . "/api/json";

my $req = HTTP::Request->new( GET => $viewStatusURL );
$req->authorization_basic( $userName, $password );
my $ua = LWP::UserAgent->new( ssl_opts => { SSL_verify_mode => 'SSL_VERIFY_NONE' } );
my $res = $ua->request($req);

my $jobNo = 0;
my @alertCnts = (0, 0, 0, 0);

if ( $res->is_success ) {
  $exitCode = 0;
  $retStr = "";
  my $json = new JSON;
  my $viewJSON = $json->decode( $res->content );

  for my $job( @{$viewJSON->{jobs}} ) {
    $jobNo += 1;
    my $jobStatus = 3;
    my $lastSuccessDaysAgo = -1;
    my $msg = "";
    my $jobURL = $job->{url} . "lastSuccessfulBuild/api/json?tree=timestamp,duration";

    $req->uri( $jobURL );
    $res = $ua->request($req);

    if ( $res->is_success ) {
      my $jobJSON = $json->decode( $res->content );
      my $lastSuccessfulBuildTs = $jobJSON->{timestamp} + $jobJSON->{duration};
      my $nowTs = time() * 1000;

      $lastSuccessDaysAgo = ($nowTs - $lastSuccessfulBuildTs ) / $dayMilliseconds;

      if ( $lastSuccessDaysAgo > $criticalDaysAgo) {
        $jobStatus = 2;
      } elsif ( $lastSuccessDaysAgo > $warningDaysAgo ) {
        $jobStatus = 1;
      } else {
        $jobStatus = 0;
      }
    } else {
      $msg = "UNKNOWN, status retrieval failure: $res->{status_line}";
    }

    my $jobName = $job->{name};

    $jobName =~ tr/ ()/_/;
    $perfData = $perfData . sprintf("\n%s=%.2f", $jobName, $lastSuccessDaysAgo);
    $retStr = $retStr . sprintf("\n %2d. %-60s - %-10s days ago: %.1f %s", $jobNo, $job->{name}, $alertStrs[$jobStatus], $lastSuccessDaysAgo, $msg);
    #$retStr = $retStr . "\n[" . $jobNo . "] " . $job->{name} . " - " . $alertStrs[$jobStatus] . ", health: " . $health . "%" ;
    $exitCode = ( $exitCode > $jobStatus ? $exitCode : $jobStatus);
    $alertCnts[$jobStatus] += 1;
  }
} else {
  $retStr = "Failed retrieving status for view $viewName ($res->{status_line})";
    $exitCode = 3;
}

print $alertStrs[$exitCode] . " - '" . $viewName . "' view: ";
print ($jobNo > 0 ? $jobNo . " jobs checked" : "" );

for my $i ( 0 .. $#alertCnts ) {
  print ($alertCnts[$i] > 0 ? ", ". $alertCnts[$i] . " " . $alertStrs[$i] : "" );
}

print $retStr . " | " . $perfData . "\n";
exit $exitCode;

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
# (c) 2015 Piotr Chromiec, RTBHouse
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

my $criticalThreshold;

if ( $numArgs == 5 ){
   $ciMasterUrl = $ARGV[0];
   $userName = $ARGV[1];
   $password = $ARGV[2];
   $jobName = $ARGV[3];
   $criticalThreshold = $ARGV[4];
} else {
  print "\nA nagios plugin for checking specified job\n";
  print "\nUsage: check_jenkins_job.pl url user_name password job_name critical_health_threshold\n";
  exit $exitCode;
}

my $jobStatusUrlPrefix = $ciMasterUrl . "/job/" . uri_escape($jobName);
my $jobStatusURL = $jobStatusUrlPrefix . "/api/json";

my $ua = LWP::UserAgent->new(
  ssl_opts => { SSL_verify_mode => 'SSL_VERIFY_NONE' },
  );
my $req = HTTP::Request->new( GET => $jobStatusURL );
$req->authorization_basic( $userName, $password );
my $res = $ua->request($req);

if ( $res->is_success ) {
  my $json = new JSON;

  my $obj = $json->decode( $res->content );

  my $health = $obj->{healthReport}->[0]->{score};

  if ( $health == 100 ) {
      $retStr = "Last build OK";
      $exitCode = 0;
  } else {
      $retStr = "Health score is: " . $health."%" ;
      $exitCode = ( $health > $criticalThreshold ? 1 : 2 );
  }
} else {
    $retStr = "Failed retrieving status for job $jobName via API (API status line: $res->{status_line})";
    $exitCode = 3;
}
    
print $alertStrs[$exitCode] . " - $retStr\n";
exit $exitCode;

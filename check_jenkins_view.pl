#!/usr/bin/perl
# A nagios plugin for checking all jobs in specified Jenkins view
#
# (c) 2015 Piotr Chromiec, RTBHouse

use strict;
use LWP::UserAgent;
use JSON;
use DateTime;
use URI::Escape;

my $retStr = "Unknown - plugin error";
my $perfData = "";
my @alertStrs = ("OK", "WARNING", "CRITICAL", "UNKNOWN");
my $exitCode = 3;
my $numArgs = $#ARGV + 1;

my $ciMasterUrl;
my $viewName;

my $userName;
my $password;

my $criticalThreshold;
my $warningThreshold;

if ( $numArgs == 6 ){
   $ciMasterUrl = $ARGV[0];
   $userName = $ARGV[1];
   $password = $ARGV[2];
   $viewName = $ARGV[3];
   $criticalThreshold = $ARGV[4];
   $warningThreshold = $ARGV[5];
} else {
  print "\nA nagios plugin for checking all jobs in specified Jenkins view\n";
  print "\nUsage: check_jenkins_view.pl url user_name password view_name critical_health_threshold warning_health_threshold\n";
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
    my $health = -1;
    my $msg = "";
    my $jobURL = $job->{url} . "/api/json";
    $req->uri( $jobURL );
    $res = $ua->request($req);
    
    if ( $res->is_success ) {
      my $jobJSON = $json->decode( $res->content );
      $health = $jobJSON->{healthReport}->[0]->{score};

      if ( $health < $criticalThreshold ) {
        $jobStatus = 2;
      } elsif ( $health < $warningThreshold ) {
        $jobStatus = 1;
      } else {
        $jobStatus = 0;
      }
    } else {
      $msg = "UNKNOWN, status retrieval failure: $res->{status_line}";
    }

    my $jobName = $job->{name};
    $jobName =~ tr/ ()/_/;
    $perfData = $perfData . sprintf("\n%s=%d", $jobName, $health) ;
    $retStr = $retStr . sprintf("\n %d. %-50s - %-10s health: %d%% %s", $jobNo, $job->{name}, $alertStrs[$jobStatus], $health, $msg);
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

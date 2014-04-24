#!/usr/bin/perl
# Author: Dave Stern (dave@davestern.com)

use lib '/usr/lib/nagios/plugins';
use utils qw(%ERRORS $TIMEOUT);

use strict;
use warnings;
use JSON;
use LWP::UserAgent;
use Getopt::Std;

sub main {

    my %options=();
    getopts("c:hs:p:u:vw:", \%options);

    my $ciHost   = $options{'s'};
    my $username = $options{'u'};
    my $password = $options{'p'};
    my $warning  = $options{'w'};
    my $critical = $options{'c'};

    my $retStr;
    my $exitCode;

    if($options{'h'})
    {
        $retStr = usage();
    }
    elsif ($ciHost && ! ($warning || $critical))
    {
        # Fail if no CI host specified or no alert threshold values
        $retStr = usage();
    }
    else
    {
        # Continue if input checks pass

        my $nodeStatusUrl = $ciHost . "/computer/api/json";

        my $ua = LWP::UserAgent->new;
        my $req = HTTP::Request->new(GET => $nodeStatusUrl);

        if ($username)
        {
            $req->authorization_basic($username, $password);
        }

        my $res = $ua->request($req);

        if ($res->is_success)
        {
            my $json = new JSON;
            my $obj = $json->decode($res->content);

            my @offline;
            my $totalNodes = 0;

            for my $computer (@{$obj->{'computer'} or []})
            {
                ++$totalNodes;
                if($computer->{'offline'} eq 'true')
                {
                    push(@offline, {
                        'displayName' => $computer->{'displayName'},
                        'offlineCauseReason' => $computer->{'offlineCauseReason'}
                    });
                }
            }

            if (my $offlineNodes = scalar(@offline))
            {
                my $offlineNodeNames = join(", ", map($_->{'displayName'}, @offline));

                my $criticalThreshold = $critical;

                # Convert critical threshold to a number if it's a %
                if ($critical =~ s/\%$//)
                {
                    $criticalThreshold = $critical/100 * $totalNodes;
                }


                my $warningThreshold = $warning;

                # Convert warning threshold to a number if it's a %
                if ($warning =~ s/\%$//)
                {
                    $warningThreshold = $warning/100 * $totalNodes;
                }


                if ($offlineNodes >= $criticalThreshold)
                {
                    $retStr = "$offlineNodes/$totalNodes nodes offline >= $options{'c'} critical ($offlineNodeNames).\n";
                    $exitCode = $ERRORS{'CRITICAL'};
                }

                # Continue to check warning threshold if not critical
                if (! $exitCode && $offlineNodes >= $warningThreshold)
                {
                    $retStr = "$offlineNodes/$totalNodes nodes offline >= $options{'w'} warning ($offlineNodeNames).\n";
                    $exitCode =  $ERRORS{'WARNING'};
                }

                # Set success output if not warning
                if (! $exitCode)
                {
                    $retStr = qq|$offlineNodes/$totalNodes nodes offline < $options{'w'} warning and < $options{'c'} critical ($offlineNodeNames).|;
                    $exitCode = $ERRORS{'OK'};
                }

            }
        }
        else
        {
            # Failure connecting to CI server
            $retStr = "Failed retrieving node status via API (API status line: $res->{status_line})";
        }
    }

    print $retStr;
    exit ($exitCode || $ERRORS{'UNKNOWN'});
}

sub usage
{
    my $usage = qq|\nUsage: check_jenkins_nodes.pl -s [jenkins server hostname & path] -w [integer or %] -c [integer or %] [-h this help message] [-u username] [-p password] [-v]

    Options:

    -c critical threshold: integer or percentage (ex: 2 or 50%)
        Critical if <critical> nodes or greater are offline

    -h This help message

    -p Optional: password to the jenkins CI server

    -s Required: jenkins CI server hostname

    -u Optional: username to the jenkins CI server

    -w warning threshold: integer or percentage (ex: 2 or 50%)
        Warn if <warning> nodes or greater are offline

    -v verbose output\n\n|;

    return $usage;
}

main();

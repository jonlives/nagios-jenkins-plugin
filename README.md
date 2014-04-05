
# Overview

This repostitory contains two nagios plugins:
* check_jenkins_job_extended.pl - The original, as documented below. Designed to check for failures, not how long since success.
* check_jenkins_cron.pl - A from-scratch copy designed to check jobs that *should* build periodically.

# check_jenkins_cron.pl

## Usage

```
usage: ./check_jenkins_cron.pl -j <job> -l <url> -w <threshold> -c <threshold> [-f] [-u username -p password] [-v]

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
```

## Sample nagios configuration


Command definition

```
define command {
  command_name    check_jenkins_cron
  command_line    $USER1$/check_jenkins_cron.pl -j '$ARG1$' -l $ARG2$ -w $ARG3$ -c $ARG4$ -f -u $ARG5$ -p $ARG6$
}
```

Service definition to warn when a job hasn't built for 24 hours, and crit when it hasn't built for 36 hours.

```
define service {
  use                             local-service
  host_name                       buildserver.mycompany.com
  service_description             Jenkins - prod build
  check_interval                  1
  check_command                   check_jenkins_cron!Producuction build!buildserver.mycompany.com!86400!129600!myuser!mypassword
  contacts                        bob,bill
}
```


# nagios-jenkins-plugin (check_jenkins_job_extended.pl)

A nagios plugin for which lets you check jenkins jobs according to various criteria.

## How to use it

The plugin supports several options, which you can pass "0" to disable that particular threshold.

Usage:  check_jenkins_job_extended url jobname concurrentFailsThreshold  buildDurationThresholdMilliseconds lastStableBuildThresholdInMinutesWarn lastStableBuildThresholdInMinutesCrit

* url: The URL to your jenkins server

* username: The username for auth to your jenkins server [optional]

* password: The password for auth to your jenkins server [optional]

* jobname: The name of the jenkins job you'd like to check

* concurrentFailsThreshold: The number of concurrent failing builds it should CRIT alert on

* buildDurationThresholdMilliseconds: It will alert if the last build took longer than this number of milliseconds to complete

* lastStableBuildThresholdInMinutesWarn: WARN if it's been this number of minutes since the last stable build

* lastStableBuildThresholdInMinutesCrit: CRIT if it's been this number of minutes since the last stable build

## Example

A sample nagios command using this plugin.

```
define command {
  command_name    check_jenkins_job_ext
  command_line    $USER1$/check_jenkins_job_extended.pl $ARG1$ $ARG2$ $ARG3$ $ARG4$ $ARG5$ $ARG6$ $ARG7$ $ARG8$
}
```

A sample nagios service using the above command to warn when it's been 4 mins since the last stable build, and crit when it's been 20.

```
define service {
  use                             local-service
  host_name                 	    buildserver.mycompany.com
  service_description             Jenkins - prod build
  check_interval                  1
  check_command                   check_jenkins_job_ext!http://buildserver.mycompany.com!prod!0!0!4!20
  contacts						bob,bill
}
```

# nagios-jenkins-plugin

A nagios plugin for which lets you check jenkins jobs according to various criteria.

## How to use it

The plugin supports several options, which you can pass "0" to disable that particular threshold.

Usage:  check_jenkins_job_extended url jobname concurrentFailsThreshold concurrentUnstableThreshold buildDurationThresholdMilliseconds lastStableBuildThresholdInMinutesWarn lastStableBuildThresholdInMinutesCrit

* url: The URL to your jenkins server

* jobname: The name of the jenkins job you'd like to check

* concurrentFailsThreshold: The number of concurrent failing builds it should CRIT alert on

* concurrentUnstableThreshold: The number of concurrent unstable builds it should CRIT alert on

* buildDurationThresholdMilliseconds: It will alert if the last build took longer than this number of milliseconds to complete

* lastStableBuildThresholdInMinutesWarn: WARN if it's been this number of minutes since the last stable build

* lastStableBuildThresholdInMinutesCrit: CRIT if it's been this number of minutes since the last stable build

## Example

A sample nagios command using this plugin.

```
define command {
  command_name    check_jenkins_job_ext
  command_line    $USER1$/check_jenkins_job_extended.pl $ARG1$ $ARG2$ $ARG3$ $ARG4$ $ARG5$ $ARG6$ $ARG7$ 
}
```

A sample nagios service using the above command to warn when it's been 4 mins since the last stable build, and crit when it's been 20.

```
define service {
  use                             local-service
  host_name                 	    buildserver.mycompany.com
  service_description             Jenkins - prod build
  check_interval                  1
  check_command                   check_jenkins_job_ext!http://buildserver.mycompany.com!prod!0!0!0!4!20
  contacts						bob,bill
}
```
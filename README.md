# RHEL Patch By Date

## Overview
Many Enterprise teams that manage Red Hat Enterprise Linux (RHEL) systems have multiple environments.  Some have just two, Development (Dev) and Production (Prod), but others have as many as five (Sandbox [SBX], Dev, Quality Assurance [QA], Performance Testing [Perf], and Prod).

Updates come and updates go.  However, many require, if not demand, that updates roll through all phases before they hit the Prod servers.  The problem: You have to let updates soak for several days, if not weeks, before you can move deploy  them to the next environment.

Fortunately, SUSE Linux Enterprise Server (SLES) allows you to do this with Zypper by passing the '--date' option.  Unfortunately, RHEL (which includes Fedora, CentOS, AlmaLinux, Rocky Linux, and Oracle Linux, among others) do not have this feature because they all rely on YUM (Yellowdog Update Manager).  So, how can you make sure that you only deploy the updates to your Prod environment that were tested in the SBX, Dev, QA, and Perf systems?

You can clone. I guess.  If that works for you.  You can also make a detailed list of the updates only only apply those very specific updates through your rollout.

Then there's the the script route.   Given that this was pretty much mandated on my team, it became clear that the script option was the best and most simple route.  Lots of searching happened and, no, we were unable to locate anything that worked.  Sure, there are tools out there that you can use to fully encrypt all of your unencrypted EBS volumes from AWS, but these one seemed to elude us.

## Compatibility
This was written and tested on RHEL 8.3 and 7.8, but should work on any YUM-based system.  Though, the return of the following command may warrant some small modifications:

    yum updateinfo info security | grep -E "Update ID:|Updated:"

The formatting is different for RHEL 7 and 8, so it'll probably be different for your distro.

## Installation
There really isn't an installation. Just download it and run it.

## Useage
You can execute the script by running:

    update-by-date.sh <date>

The date is in the YYYY-MM-DD format (ISO-8601) and yes, you include the hyphens.
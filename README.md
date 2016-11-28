# dssh
Helper script for quickly connecting to a docker instance running in an AWS ECS cluster.

# Prerequisites
This script depends on the 'jq' package for reading JSON files in bash:

  https://stedolan.github.io/jq/manual/

It also depends on the AWS CLI and assumes it is logged in and set up with enough permissions to read from the AWS ECS and EC2 service calls.

Finally, it assumes there is only one running task for the URL you pass to it, as it was written in an environment where that is a safe assumption.

# Installation
Clone or download the script to somewhere sensible (e.g. /opt) and make sure everyone can execute it - ```chmod +x ./dssh.sh```

For system-wide availability in Linux, move the script to /usr/local/bin/dssh

# Usage
The script expects just one thing - the environment domain of the container / task you want to get to, e.g.

```
dssh mycontainer.mydomain.com
```

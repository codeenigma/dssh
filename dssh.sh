#!/bin/bash

##############################################################################
# This script finds the correct instance for a given container environment URL
# and logs the user in, providing the Docker command for logging into the
# container on the instance.
#
# See: https://github.com/codeenigma/dssh
#
# 'jq' documentation: https://stedolan.github.io/jq/manual/
#
# Copyright Greg Harvey, 2016
##############################################################################

# Get a list of running tasks
aws ecs list-tasks > /tmp/tasks.json

# Get full details of running tasks
echo " " && echo ">> Fetching all tasks"
jq .taskArns[] /tmp/tasks.json | aws ecs describe-tasks --tasks $(sed -E 's/^\".*\/(.*)\"/\1/') > /tmp/task-details.json

# For each task extract the task definition ARN out to file
jq .tasks[].taskDefinitionArn /tmp/task-details.json | sed -E 's/^\"(.*)\"/\1/' > /tmp/task-definition-arns.txt

# Find which task and task definition we want
for arn in `cat /tmp/task-definition-arns.txt`; do
  # Load specific task definition details (it's the definition that contains the listening URL info)
  aws ecs describe-task-definition --task-definition $arn > /tmp/task.json
  # Load the URL tasks created by this task definition will listen on
  ENVIRONMENT_URL=$(jq '.taskDefinition.containerDefinitions[].environment[] | select(.name=="DOMAIN") | .value' /tmp/task.json | sed -E 's/^\"(.*)\"/\1/')

  # Check if the URL matches the one we're looking for
  if [ "$ENVIRONMENT_URL" == "$1" ]; then
    echo " " && echo ">> Matching task found, looking up EC2 instance for container with URL ${ENVIRONMENT_URL}" && echo " "

    # Look up the ECS container instance ID (not the same as the EC2 instance ID) in our running task matching this task definition
    # IMPORTANT: we assume one task per task definition for our purposes, but this may not be the case in all environments
    ARN_STRING="\"$arn\""
    COMMAND="jq '.tasks[] | select(.taskDefinitionArn==${ARN_STRING}) | .containerInstanceArn' /tmp/task-details.json"
    EC2_ARN=$(eval $COMMAND)
    EC2_CINSTANCE=$(echo $EC2_ARN | sed -E 's/^\".*\/(.*)\"/\1/')

    # Look up the actual EC2 instance ID from the container instance data
    aws ecs describe-container-instances --container-instances ${EC2_CINSTANCE} > /tmp/container.json
    EC2_INSTANCE_ID=$(jq .containerInstances[].ec2InstanceId /tmp/container.json | sed -E 's/^\"(.*)\"/\1/')
    echo "EC2 Instance ID: ${EC2_INSTANCE_ID}"

    # Look up the public IP address of the instance by calling the ec2 service with the instance ID
    aws ec2 describe-instances --instance-ids ${EC2_INSTANCE_ID} > /tmp/instance.json
    INSTANCE_IP=$(jq .Reservations[].Instances[].PublicIpAddress /tmp/instance.json | sed -E 's/^\"(.*)\"/\1/')
    echo "EC2 Instance IP address: ${INSTANCE_IP}" && echo " "

    # Use the local API on the EC2 instance to look up the Docker container ID
    # @TODO: consider using ecs-cli for this: http://docs.aws.amazon.com/AmazonECS/latest/developerguide/cmd-ecs-cli-ps.html
    echo ">> Looking up Docker container IP on host EC2 instance" && echo " "
    # Need to get the task ARN, the ARN in this loop is the task *definition* ARN, different data
    COMMAND="jq '.tasks[] | select(.taskDefinitionArn==${ARN_STRING}) | .taskArn' /tmp/task-details.json"
    TASK_ARN=$(eval $COMMAND)
    TASK_ARN=$(echo $TASK_ARN | sed -E 's/^\"(.*)\"/\1/')
    # SSH into the EC2 instance and hit the local introspective API to get the docker data
    # See: http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-agent-introspection.html
    COMMAND="ssh ec2-user@${INSTANCE_IP} 'curl http://localhost:51678/v1/tasks?taskarn=${TASK_ARN}' > /tmp/docker-container.json"
    eval $COMMAND
    DOCKER_ID=$(jq .Containers[].DockerId /tmp/docker-container.json | sed -E 's/^\"(.*)\"/\1/')
    echo " " && echo "Docker Container ID: ${DOCKER_ID}" && echo " "

    # Clean up all the files we made
    echo ">> Clearing up"
    rm /tmp/task.json
    rm /tmp/tasks.json
    rm /tmp/task-details.json
    rm /tmp/task-definition-arns.txt
    rm /tmp/container.json
    rm /tmp/instance.json
    rm /tmp/docker-container.json

    # Write some instructions to the end user
    echo " " && echo "#######################################################" && echo " "
    echo ">> YOU ARE NOW LOGGED INTO THE CORRECT EC2 INSTANCE! <<"
    echo " " && echo "Copy and paste this command into the bash prompt:" && echo " "
    echo "  docker exec -it ${DOCKER_ID} bash"
    echo " " && echo "######################################################" && echo " "

    # Login to the EC2 instance so we're ready to roll!
    ssh -t ec2-user@${INSTANCE_IP} '/bin/bash'
    exit
  fi
done

# We didn't find a matching container
echo ">> No matching container found!" && echo " "

# Clean up all the files we made
echo ">> Clearing up" && echo " "
rm /tmp/task.json
rm /tmp/tasks.json
rm /tmp/task-details.json
rm /tmp/task-definition-arns.txt

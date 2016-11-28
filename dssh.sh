#!/bin/bash

#########################################
# This script finds the correct instance
# for a given container environment URL
# and logs the user in, providing the
# Docker command for logging into the
# container on the instance.
#########################################

# Get a list of running tasks
aws ecs list-tasks > /tmp/tasks.json

# Get full details of running tasks
echo " "
echo ">> Fetching all tasks"
jq .taskArns[] /tmp/tasks.json | aws ecs describe-tasks --tasks $(sed -E 's/^\".*\/(.*)\"/\1/') > /tmp/task-details.json

# Copy the ARNs of the tasks out to file
jq .tasks[].taskDefinitionArn /tmp/task-details.json | sed -E 's/^\"(.*)\"/\1/' > /tmp/task-definition-arns.txt

# Find which task we want
CONTAINER_FOUND=0
for arn in `cat /tmp/task-definition-arns.txt`; do
  aws ecs describe-task-definition --task-definition $arn > /tmp/task.json
  ENVIRONMENT_URL=$(jq '.taskDefinition.containerDefinitions[].environment[] | select(.name=="DOMAIN") | .value' /tmp/task.json | sed -E 's/^\"(.*)\"/\1/')

  if [ "$ENVIRONMENT_URL" == "$1" ]; then
    CONTAINER_FOUND=1
    echo " "
    echo ">> Matching task found, looking up EC2 instance for container with URL ${ENVIRONMENT_URL}"
    echo " "

    # Look up the ECS container instance ID (not the same as the EC2 instance ID)
    ARN_STRING="\"$arn\""
    COMMAND="jq '.tasks[] | select(.taskDefinitionArn==${ARN_STRING}) | .containerInstanceArn' /tmp/task-details.json"
    EC2_ARN=$(eval $COMMAND)
    EC2_CINSTANCE=$(echo $EC2_ARN | sed -E 's/^\".*\/(.*)\"/\1/')

    # Look up the actual EC2 instance ID from the container instance data
    aws ecs describe-container-instances --container-instances ${EC2_CINSTANCE} > /tmp/container.json
    EC2_INSTANCE_ID=$(jq .containerInstances[].ec2InstanceId /tmp/container.json | sed -E 's/^\"(.*)\"/\1/')
    echo "EC2 Instance ID: ${EC2_INSTANCE_ID}"

    # Look up the public IP address of the instance
    aws ec2 describe-instances --instance-ids ${EC2_INSTANCE_ID} > /tmp/instance.json
    INSTANCE_IP=$(jq .Reservations[].Instances[].PublicIpAddress /tmp/instance.json | sed -E 's/^\"(.*)\"/\1/')
    echo "EC2 Instance IP address: ${INSTANCE_IP}"
    echo " "

    # Use the local API on the EC2 instance to look up the Docker container ID
    echo ">> Looking up Docker container IP on host EC2 instance"
    echo " "
    COMMAND="jq '.tasks[] | select(.taskDefinitionArn==${ARN_STRING}) | .taskArn' /tmp/task-details.json"
    TASK_ARN=$(eval $COMMAND)
    TASK_ARN=$(echo $TASK_ARN | sed -E 's/^\"(.*)\"/\1/')
    COMMAND="ssh ec2-user@${INSTANCE_IP} 'curl http://localhost:51678/v1/tasks?taskarn=${TASK_ARN}' > /tmp/docker-container.json"
    eval $COMMAND
    DOCKER_ID=$(jq .Containers[].DockerId /tmp/docker-container.json | sed -E 's/^\"(.*)\"/\1/')
    echo " "
    echo "Docker Container ID: ${DOCKER_ID}"
    echo " "

    # Clean up all the other files we made
    echo ">> Clearing up"
    rm /tmp/task.json
    rm /tmp/tasks.json
    rm /tmp/task-details.json
    rm /tmp/task-definition-arns.txt
    rm /tmp/container.json
    rm /tmp/instance.json
    rm /tmp/docker-container.json

    # Write some instructions to the end user
    echo " "
    echo "#######################################################"
    echo " "
    echo ">> YOU ARE NOW LOGGED INTO THE CORRECT EC2 INSTANCE! <<"
    echo " "
    echo "Copy and paste this command into the bash prompt:"
    echo " "
    echo "  docker exec -it ${DOCKER_ID} bash"
    echo " "
    echo "######################################################"
    echo " "

    # Login to the EC2 instance
    ssh -t ec2-user@${INSTANCE_IP} '/bin/bash'
    exit
  fi
done

if [ $CONTAINER_FOUND == 0 ]; then
  # We didn't find a matching container
  echo ">> No matching container found!"
  echo " "
fi

# Clean up all the files we made
echo ">> Clearing up"
rm /tmp/task.json
rm /tmp/tasks.json
rm /tmp/task-details.json
rm /tmp/task-definition-arns.txt

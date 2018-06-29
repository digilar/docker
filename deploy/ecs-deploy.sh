#!/bin/bash

ECS_REGION=$1   # AWS region to deploy to
ENVIRONMENT=$2  # Name of the environment (e.g. canary, staging, production)
ECR_NAME=$3     # Name of the service/application
HASH=$4         # Hash for the image version (e.g git commit hash)

[[ -z "$ECS_REGION" ]] && { echo "must pass an region" ; exit 1; }
[[ -z "$ECR_NAME" ]] && { echo "must pass a name" ; exit 1; }
[[ -z "$ENVIRONMENT" ]] && { echo "must pass an environment" ; exit 1; }
[[ -z "$HASH" ]] && { echo "must pass a hash" ; exit 1; }

function getParameter() {
  local _val=$(aws ssm get-parameters --region $ECS_REGION --names "/$ENVIRONMENT/$1/$2" --with-decryption --query Parameters[0].Value)
  local _val=`echo $_val | sed -e 's/^"//' -e 's/"$//'`
  echo "$_val"
}

# GLOBAL FOR ENVIRONMENT
AWS_ACCOUNT_ID=$(getParameter "common" "AWS_ACCOUNT_ID")
ECS_CLUSTER_NAME=$(getParameter "common" "ECS_CLUSTER_NAME")
LOG_GROUP=$(getParameter "common" "LOG_GROUP")

# SERVICE SPECIFIC PARAMETERS
ECS_TASK_DEFINITION_NAME=$(getParameter "$ECR_NAME" "ECS_TASK_DEFINITION_NAME")
ECS_SERVICE_NAME=$(getParameter "$ECR_NAME" "ECS_SERVICE_NAME")

PORT=$(getParameter "$ECR_NAME" "PORT")
COMMAND=$(getParameter "$ECR_NAME" "COMMAND")

TASK_CPU=$(getParameter "$ECR_NAME" "TASK_CPU")
TASK_MEMORY=$(getParameter "$ECR_NAME" "TASK_MEMORY")
TASK_MEMORY_RESERVATION=$(getParameter "$ECR_NAME" "TASK_MEMORY_RESERVATION")

NETWORK_MODE=$(getParameter "$ECR_NAME" "NETWORK_MODE")
LAUNCH_TYPE=$(getParameter "$ECR_NAME" "LAUNCH_TYPE")

EXECUTION_ROLE_ARN=$(getParameter "$ECR_NAME" "EXECUTION_ROLE_ARN")
TASK_ROLE_ARN=$(getParameter "$ECR_NAME" "TASK_ROLE_ARN")

VERSION=$ENVIRONMENT-$HASH

echo "----- Deploying: $ECR_NAME to cluster: $ECS_CLUSTER_NAME -----"
echo "CPU: $TASK_CPU"
echo "MEM: $TASK_MEMORY"
echo "TYPE: $LAUNCH_TYPE"
echo "MODE: $NETWORK_MODE"

aws configure set default.region $ECS_REGION

# Authenticate against ECR
eval $(aws ecr get-login --no-include-email)

# Build and push the image
docker build -t $ECR_NAME .

docker tag $ECR_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:$VERSION
docker tag $ECR_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:latest

docker push $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:$VERSION
docker push $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:latest

task_template='[
  {
    "name": "%s",
    "image": "%s.dkr.ecr.%s.amazonaws.com/%s:%s",
    "essential": true,
    "cpu": %s,
    "memory": %s,
    "memoryReservation": %s,
    "portMappings": [
      {
        "containerPort": %s,
        "hostPort": %s,
        "protocol": "tcp"
      }
    ],
    "environment" : [
      { "name" : "ENVIRONMENT", "value" : "%s" }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "%s",
            "awslogs-region": "%s",
            "awslogs-stream-prefix": "%s-"
        }
    },
    "command": [
      "%s",
      "%s",
      "%s",
      "%s",
      "%s",
      "%s"
    ]
  }
]'

task_def=$(printf "$task_template" $ECR_NAME $AWS_ACCOUNT_ID $ECS_REGION $ECR_NAME $VERSION $TASK_CPU $TASK_MEMORY $TASK_MEMORY_RESERVATION $PORT $PORT $ENVIRONMENT $LOG_GROUP $ECS_REGION $LOG_PREFIX $ECR_NAME $COMMAND)

echo "Register task definition:"
echo "$task_def"

# Register task definition
json=$(aws ecs register-task-definition --container-definitions "$task_def" --family "$ECS_TASK_DEFINITION_NAME" --requires-compatibilities $LAUNCH_TYPE --cpu $TASK_CPU --memory $TASK_MEMORY --network-mode $NETWORK_MODE --execution-role-arn $EXECUTION_ROLE_ARN --task-role-arn $TASK_ROLE_ARN)

# Grab revision # using regular bash and grep
revision=$(echo "$json" | grep -o '"revision": [0-9]*' | grep -Eo '[0-9]+')

# Deploy revision
aws ecs update-service --cluster "$ECS_CLUSTER_NAME" --service "$ECS_SERVICE_NAME" --task-definition "$ECS_TASK_DEFINITION_NAME":"$revision"

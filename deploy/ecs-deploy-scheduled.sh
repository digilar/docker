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

VERSION=$ENVIRONMENT-$HASH

echo "----- Deploying: $ECR_NAME to environment: $ENVIRONMENT -----"

aws configure set default.region $ECS_REGION

# Authenticate against ECR
eval $(aws ecr get-login --no-include-email)

# Build and push the image
docker build -t $ECR_NAME .

docker tag $ECR_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:$VERSION
docker tag $ECR_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:latest-$ENVIRONMENT
docker tag $ECR_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:latest

docker push $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:$VERSION
docker push $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:latest-$ENVIRONMENT
docker push $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:latest
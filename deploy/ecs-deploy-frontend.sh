#!/bin/bash

ECS_REGION=$1   # AWS region where parameters can be found
ENVIRONMENT=$2  # Name of the environment (e.g. canary, staging, production)
ECR_NAME=$3     # Name of the service/application
ROOT_ENVIRONMENT=${ENVIRONMENT}

[[ -z "$ECS_REGION" ]] && { echo "must pass a region" ; exit 1; }
[[ -z "$ECR_NAME" ]] && { echo "must pass a name" ; exit 1; }
[[ -z "$ENVIRONMENT" ]] && { echo "must pass an environment" ; exit 1; }

function getParameter {
  local _val=$(aws ssm get-parameters --region $ECS_REGION --names "/$ENVIRONMENT/$1/$2" --with-decryption --query Parameters[0].Value)
  local _val=`echo $_val | sed -e 's/^"//' -e 's/"$//'`
  echo "$_val"
}

# For both environments
export API_ENDPOINT=$(getParameter "common" "API_ENDPOINT")

# For both environments, but values can differ
export AWS_DISTRIBUTION=$(getParameter "$ECR_NAME" "CLOUDFRONT_DISTRIBUTION")
export AWS_BUCKET=$(getParameter "$ECR_NAME" "S3_BUCKET")
export AWS_REGION=$(getParameter "$ECR_NAME" "S3_REGION")

export CLIENT_ID=$(getParameter "$ECR_NAME" "CLIENT_ID")
export CLIENT_SECRET=$(getParameter "$ECR_NAME" "CLIENT_SECRET")

export ENVIRONMENT_NAME=${ENVIRONMENT}

# For single environment
if [ "$ECR_NAME" = "arch-cms" ]
then 
  export BABEL_ENDPOINT=$(getParameter "$ECR_NAME" "BABEL_ENDPOINT")
fi 

if [ "$ECR_NAME" = "babel-app" ]
then 
  export ZENDESK_KEY=$(getParameter "$ECR_NAME" "ZENDESK_KEY")
  export EMAIL_VALIDATOR_LOCATION=$(getParameter "$ECR_NAME" "EMAIL_VALIDATOR_LOCATION")
  export EMAIL_VALIDATOR_APIKEY=$(getParameter "$ECR_NAME" "EMAIL_VALIDATOR_APIKEY")
fi 

echo "Exported ENVIRONMENT_NAME: ${ENVIRONMENT_NAME}"
echo "----- Deploying: $ECR_NAME to bucket: $AWS_BUCKET -----"
echo "AWS_DISTRIBUTION: $AWS_DISTRIBUTION"
echo "AWS_REGION: $AWS_REGION"

ember deploy "$ENVIRONMENT" --activate

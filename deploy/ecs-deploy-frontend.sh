#!/bin/bash

ECS_REGION=$1   # AWS region where parameters can be found
ENVIRONMENT=$2  # Name of the environment (e.g. canary, staging, production)
ECR_NAME=$3     # Name of the service/application
ROOT_ENVIRONMENT=${ENVIRONMENT}

[[ -z "$ECS_REGION" ]] && { echo "must pass a region" ; exit 1; }
[[ -z "$ECR_NAME" ]] && { echo "must pass a name" ; exit 1; }
[[ -z "$ENVIRONMENT" ]] && { echo "must pass an environment" ; exit 1; }

if [[ "${ENVIRONMENT}" == "production" ]]
then
  ENVIRONMENT=$(aws ssm get-parameter --region ${ECS_REGION} --name "/production/deploy/StackName" --query Parameter.Value)
  ENVIRONMENT=`echo ${ENVIRONMENT} | sed -e 's/^"//' -e 's/"$//'`
fi

function getParameter {
  local _val=$(aws ssm get-parameters --region ${ECS_REGION} --names "/$1/$2/$3" --with-decryption --query Parameters[0].Value)
  local _val=`echo ${_val} | sed -e 's/^"//' -e 's/"$//'`
  echo "$_val"
}

# For both environments
export API_ENDPOINT=$(getParameter "${ENVIRONMENT}" "common" "API_ENDPOINT")

# For both environments, but values can differ
export AWS_DISTRIBUTION=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "CLOUDFRONT_DISTRIBUTION")
export AWS_BUCKET=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "S3_BUCKET")
export AWS_REGION=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "S3_REGION")

export CLIENT_ID=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "CLIENT_ID")
export CLIENT_SECRET=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "CLIENT_SECRET")

export ENVIRONMENT_NAME=${ROOT_ENVIRONMENT}
export BABEL_ENDPOINT=$(getParameter "${ENVIRONMENT}" "common" "BABEL_ENDPOINT")


if [[ "$ECR_NAME" = "babel-app" ]]
then 
  export ZENDESK_KEY=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "ZENDESK_KEY")
  export EMAIL_VALIDATOR_LOCATION=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "EMAIL_VALIDATOR_LOCATION")
  export EMAIL_VALIDATOR_APIKEY=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "EMAIL_VALIDATOR_APIKEY")
fi 

echo "Exported ENVIRONMENT_NAME: ${ENVIRONMENT_NAME}"
echo "----- Deploying: $ECR_NAME to bucket: $AWS_BUCKET -----"
echo "AWS_DISTRIBUTION: $AWS_DISTRIBUTION"
echo "AWS_REGION: $AWS_REGION"

ember deploy "$ROOT_ENVIRONMENT" --activate

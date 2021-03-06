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
export KONTO_AUTHORITY=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "KONTO_AUTHORITY")
export KONTO_CLIENT_ID=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "KONTO_CLIENT_ID")
export LEGION_URL=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "LEGION_URL")
export ARCH_URL=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "ARCH_URL")
export BABEL_URL=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "BABEL_URL")

export CLIENT_ID=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "CLIENT_ID")
export CLIENT_SECRET=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "CLIENT_SECRET")

export ENVIRONMENT_NAME=${ROOT_ENVIRONMENT}
export BABEL_ENDPOINT=$(getParameter "${ENVIRONMENT}" "common" "BABEL_ENDPOINT")
export RECORDED_SPEECH_ENDPOINT=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "RECORDED_SPEECH_ENDPOINT ")
export FILE_ENDPOINT=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "FILE_ENDPOINT")

echo "Exporting ${ENVIRONMENT} $ECR_NAME EMAIL_VALIDATOR_LOCATION"
export EMAIL_VALIDATOR_LOCATION=$(getParameter "${ENVIRONMENT}" "frontend" "EMAIL_VALIDATOR_LOCATION")
echo "Exporting ${ENVIRONMENT} $ECR_NAME EMAIL_VALIDATOR_APIKEY"
export EMAIL_VALIDATOR_APIKEY=$(getParameter "${ENVIRONMENT}" "frontend" "EMAIL_VALIDATOR_APIKEY")


if [[ "$ECR_NAME" = "arch-cms" ]]
then
  echo "Exporting ${ENVIRONMENT} $ECR_NAME FILE_ENDPOINT"
  export FILE_ENDPOINT=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "FILE_ENDPOINT")
fi

if [[ "$ECR_NAME" = "babel-app" ]]
then
  echo "Exporting ${ENVIRONMENT} $ECR_NAME ZENDESK_KEY"
  export ZENDESK_KEY=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "ZENDESK_KEY")
  echo "Exporting ${ENVIRONMENT} $ECR_NAME ILT_API_BASE_URL"
  export ILT_API_BASE_URL=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "ILT_API_BASE_URL")
  echo "Exporting ${ENVIRONMENT} $ECR_NAME PUSHER_KEY"
  export PUSHER_KEY=$(getParameter "${ENVIRONMENT}" "$ECR_NAME" "PUSHER_KEY")
fi 

echo "Exported ENVIRONMENT_NAME: ${ENVIRONMENT_NAME}"
echo "Deploy variables from: ${ENVIRONMENT}"
echo "----- Deploying: $ECR_NAME to bucket: $AWS_BUCKET -----"
echo "AWS_DISTRIBUTION: $AWS_DISTRIBUTION"
echo "AWS_REGION: $AWS_REGION"

ember deploy "$ROOT_ENVIRONMENT" --activate

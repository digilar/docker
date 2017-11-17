#!/bin/bash

##############################################################
# Typical usage:
# ./deploy.sh mgr-dns-name my-service 80:80 [aws-acct-number].dkr.ecr.[aws-region].amazonaws.com/[repo-name]/[image-name]:[image-tag] [my.pem]
# Example:
# ./deploy.sh ec2-52-59-209-188.eu-central-1.compute.amazonaws.com frontend-api 9000:9000 720340613074.dkr.ecr.eu-central-1.amazonaws.com/haaartland/frontend-api:1.0.6-f58d11b ~/.ssh/Docker_for_AWS_eu-central-1_KeyPair.pem
##############################################################

MGR_DNS_NAME=$1 # Public DNS name of one of the mgr nodes of the docker swarm cluster (in our case on AWS)
SERVICE_NAME=$2 # The name to publish on the overlay network for the service (so that other services can call it internally within the swarm across EC2 nodes)
PORTS=$3 # The port mapping for any external exposure for the service
FULL_IMAGE_NAME=$4 # The full image name to deploy (in our case prefixed with the private ECR repo name)
PEM=${5:-Empty} # PEM is typically: ~/.ssh/Docker_for_AWS_eu-central-1_KeyPair.pem (optional, if the script is run on CircleCI )

echo ""
echo "----- Deploying: $SERVICE_NAME to AWS docker swarm with manager node: $MGR_DNS_NAME -----"

if [[ $PEM != Empty ]]  # Allowing optional parameter for .pem file
then
    MGR_SSH="ssh -o StrictHostKeyChecking=no -i ${PEM} docker@${MGR_DNS_NAME}"
else
    MGR_SSH="ssh -o StrictHostKeyChecking=no docker@${MGR_DNS_NAME}"
fi
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

echo "--- MGR_SSH: ${MGR_SSH} ---"

# Create overlay network for default service discovery (if it doesn't already exist)
ALL_NETWORKS=$(${MGR_SSH} docker network ls)
echo "All networks: ${ALL_NETWORKS}"

NETWORKS=$(${MGR_SSH} docker network ls --filter name=service-discovery-network --quiet | wc -l)
if [[ "$NETWORKS" -eq 0 ]]; then
	echo "Network service-discovery-network not found, creating..."
    ${MGR_SSH} docker network create -d overlay service-discovery-network
fi

SERVICE_ID=$(${MGR_SSH} docker service ls --filter name=${SERVICE_NAME} -q)
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
if [[ -n "$SERVICE_ID" ]]
then
  echo "Service: ${SERVICE_NAME} exists. Updating it with new image..."
  ${MGR_SSH} docker service update \
                --image ${FULL_IMAGE_NAME} \
                 --with-registry-auth \
                --detach=false \
                  ${SERVICE_NAME}
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
else
  echo "Creating service: ${SERVICE_NAME}..."
  ${MGR_SSH} docker service create \
                --name ${SERVICE_NAME} \
                --network service-discovery-network \
                --publish ${PORTS} \
                --with-registry-auth \
                --detach=false \
                ${FULL_IMAGE_NAME}
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
fi

echo "Done!!!"
echo ""

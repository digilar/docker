#!/bin/bash

##############################################################
# Typical usage:
# ./deploy.sh <mgr-dns-name> <docker-user> <docker-pass> <service-name> XXXX:YYYY [repo-name]/[image-name]:[image-tag]
##############################################################

MGR_DNS_NAME=$1 # Public DNS name of one of the mgr nodes of the docker swarm cluster (in our case on AWS)
DOCKER_USER=$2 # Docker Hub Username
DOCKER_PASS=$3 # Docker Hub Password
SERVICE_NAME=$4 # The name to use for the service on the overlay network
PORTS=$5 # The port mapping for external exposure for the service
FULL_IMAGE_NAME=$6 # The full image name to deploy (in our case prefixed with the private ECR repo name)

echo ""
echo "----- Deploying: $SERVICE_NAME to AWS docker swarm with manager node: $MGR_DNS_NAME -----"

MGR_SSH="ssh -o StrictHostKeyChecking=no docker@${MGR_DNS_NAME}"
echo "--- MGR_SSH: ${MGR_SSH} ---"

# Create overlay network for default service discovery (if it doesn't already exist)
ALL_NETWORKS=$(${MGR_SSH} docker network ls)
echo "${ALL_NETWORKS}"

NETWORKS=$(${MGR_SSH} docker network ls --filter name=api_service-discovery-network --quiet | wc -l)
if [[ "$NETWORKS" -eq 0 ]]; then
	echo "Network api_service-discovery-network not found, creating..."
    ${MGR_SSH} docker network create -d overlay api_service-discovery-network
fi

# Login to DockerHub...
${MGR_SSH} docker login -u $DOCKER_USER -p $DOCKER_PASS

SERVICE_ID=$(${MGR_SSH} docker service ls --filter name=${SERVICE_NAME} -q)
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
if [[ -n "$SERVICE_ID" ]]
then
  echo "Service: ${SERVICE_NAME} exists. Updating it with new image..."
  ${MGR_SSH} docker service update \
                --image ${FULL_IMAGE_NAME} \
                --with-registry-auth \
                --env-file=.env \
                --detach=false \
                  ${SERVICE_NAME}
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
else
  echo "Creating service: ${SERVICE_NAME}..."
  ${MGR_SSH} docker service create \
                --name ${SERVICE_NAME} \
                --network api_service-discovery-network \
                --publish ${PORTS} \
                --with-registry-auth \
                --env-file=.env \
                --detach=false \
                ${FULL_IMAGE_NAME}
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
fi

echo "Done!!!"
echo ""

#!/bin/bash

# Copyright © 2018 Robin Weiss (http://www.gerdi-project.de/)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Description:
# This script builds and pushes a Docker image. After the image is built, 
# it is pushed to a Docker registry and subsequently removed from the local image list.
#
# Arguments:
# 1 - The URL of the Docker registry to which the image is pushed.
# 2 - The name of the Docker image that is to be created.
# 3 - The tag of the built Docker image.


# treat unset variables as an error when substituting, because the argument is optional
set -u

# load helper scripts
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/misc-utils.sh
source ./scripts/helper-scripts/k8s-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Pushes a specified docker image to the registry and tags it with latest and a specified tag.
# Subsequently, the image is removed from the local image list to free up space.
#
# Arguments:
#  1 - the Docker Registry URL
#  2 - the name of the Docker image to be built, excluding any tags
#  3 - the tag of the Docker image to be built
#
DockerPush() {
  local registryUrl="$1"
  local imageName="$2"
  local imageTag="$3"
  
  local image
  image="$registryUrl/$imageName:$imageTag"
  
  echo "Pushing docker image: $image" >&2
  docker push "$image"
  
  # push 'latest' tag
  
  if [ "$imageTag" != "latest" ]; then
    local latestImage
	latestImage="$registryUrl/$imageName:latest"
	
    docker tag  "$image" "$latestImage"
    docker push "$latestImage"
  fi

  # remove image from local image list
  echo "Removing docker image from local docker image list." >&2
  docker rmi "$image"
}


# Builds a Docker image.
#
# Arguments:
#  1 - the Docker Registry URL
#  2 - the name of the Docker image to be built, excluding any tags
#  3 - the tag of the Docker image to be built
#
DockerBuild() {
  local registryUrl="$1"
  local imageName="$2"
  local imageTag="$3"
  
  local image
  image="$registryUrl/$imageName:$imageTag"

  # build image
  echo "Building docker image $image." >&2
  docker build -t "$image" .
}


# If there are warfiles to be deployed, change their access rights 
# in order to allow jetty to use them.
#
# Arguments: -
#
AllowWarFileAccess() {
  local warFile
  warFile=$(ls -cB "target/"*.war | head -1)
  
  if [ -n "$warFile" ]; then
    stat -c "%a" $warFile
    chmod o+rw $warFile
  fi
}


# Retrieves the Docker image name without the preceding registry URL and
# without the image tag-
#
GetDockerImageName() {
  local gitCloneLink="$bamboo_planRepository_1_repositoryUrl"
  
  local serviceName
  serviceName=$(GetServiceType "$gitCloneLink")
  
  local repositorySlug
  repositorySlug=$(GetRepositorySlugFromCloneLink "$gitCloneLink")
  
  echo "$serviceName/$repositorySlug"
}


# The main function that is called on script execution.
#
Main() {
  ExitIfPlanVariableIsMissing "DOCKER_REGISTRY"
  
  local dockerImageTag="$1"
  if [ -z "$dockerImageTag" ]; then
    echo "You must pass the Docker image tag as first argument to the script!" >&2
	exit 1
  fi
  
  local dockerRegistryUrl=$(GetValueOfPlanVariable "DOCKER_REGISTRY")
  local dockerImageName=$(GetDockerImageName)
  
  AllowWarFileAccess
  DockerBuild "$dockerRegistryUrl" "$dockerImageName" "$dockerImageTag"
  DockerPush "$dockerRegistryUrl" "$dockerImageName" "$dockerImageTag"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
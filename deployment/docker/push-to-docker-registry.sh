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
# 1 - The tag of the built Docker image.
#
# Bamboo Plan Variables:
#  bamboo_planRepository_1_repositoryUrl 
#    The ssh clone link to the first repository of the plan.

# treat unset variables as an error when substituting, because the argument is optional
set -u

# load helper scripts
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/misc-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/k8s-utils.sh
source ./scripts/helper-scripts/docker-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################


# If there are war files to be deployed, change their access rights 
# in order to allow jetty to use them.
#
# Arguments: -
#
AllowWarFileAccess() {
  if [ -d target ]; then
    local warFile
    warFile=$(ls -cB "target/"*.war | head -1)
  
    if [ -n "$warFile" ]; then
      stat -c "%a" $warFile
      chmod o+rw $warFile
    fi
  fi
}


# Retrieves the Docker image name without the preceding registry URL and
# without the image tag.
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
  
  local dockerFileFolder="${2-.}"
  local dockerRegistryUrl=$(GetValueOfPlanVariable "DOCKER_REGISTRY")
  local dockerImageName=$(GetDockerImageName)
  
  AllowWarFileAccess
  DockerBuild "$dockerFileFolder" "$dockerRegistryUrl" "$dockerImageName" "$dockerImageTag"
  DockerPush "$dockerRegistryUrl" "$dockerImageName" "$dockerImageTag"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
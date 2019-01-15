#!/bin/bash

# Copyright © 2019 Robin Weiss (http://www.gerdi-project.de/)
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

# This script offers helper functions that concern Docker in the GeRDI project.
 

# Builds a Docker image.
#
# Arguments:
#  1 - the folder where the docker file is stored
#  2 - the Docker Registry URL
#  3 - the name of the Docker image to be built, excluding any tags
#  4 - the tag of the Docker image to be built
#
DockerBuild() {
  local dockerFileFolder="$1"
  local registryUrl="$2"
  local imageName="$3"
  local imageTag="$4"
  
  local image
  image="$registryUrl/$imageName:$imageTag"

  # build image
  echo "Building docker image: $image" >&2
  
  if [ -z "$imageTag" ] || [ "$imageTag" = "latest" ]; then
    docker build -t "$registryUrl/$imageName:latest" \
	             "$dockerFileFolder"
  else
    docker build -t "$registryUrl/$imageName:latest" \
	             -t "$image" \
				 "$dockerFileFolder"
  fi
}


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
  
  # push latest
  local latestImage
  latestImage="$registryUrl/$imageName:latest"
  docker push "$latestImage"
  
  # remove image from local image list
  echo "Removing docker image from local docker image list." >&2
  echo $(docker rmi "$latestImage") >&2

  # push custom tag if specified
  if [ -n "$imageTag" ] && [ "$imageTag" != "latest" ]; then
    local taggedImage
    taggedImage="$registryUrl/$imageName:$imageTag"
    docker push "$taggedImage"
	
	# remove image from local image list
    echo "Removing docker image from local docker image list." >&2
    echo $(docker rmi "$taggedImage") >&2
  fi
}


# Retrieves the Docker Base Image version of a specified repository.
# Exits with 1 if the repository cannot be reached, or the Dockerfile of
# the project is not derived from the OAI-PMH image.
#  Arguments:
#  1 - the project id of the checked repository
#  2 - the repository slug of the checked repository
#  3 - the branch of the checked repository
#  4 - a username for Basic Authentication (optional)
#  5 - a password for Basic Authentication (optional)
#
GetDockerBaseImageVersion() {
  local projectId="$1"
  local slug="$2"
  local branch="$3"
  local userName="${4-}"
  local password="${5-}"
  
  local auth=""
  if [ -n "$userName" ]; then
    auth="-u $userName:$password"
  fi
  
  # read DockerFile of repository
  curl -sfX GET $auth "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$slug/browse/Dockerfile?raw&at=refs%2Fheads%2F$branch"\
        | grep -oP "(?<=FROM docker-registry\.gerdi\.research\.lrz\.de:5043/)[^\"]+"\
        | grep -oP "(?<=:).+"
}


# Compares two Docker image tags and returns 0 if the first image tag
# is lower than the second one. Checks versions, release environments and
# build numbers, e.g. 1.2.3-test4, 1.2.3-rc4, 1.2.3
# Exits with 1 if the second version is lower or equal to the first version.
#
#  Arguments:
#  1 - the first version that is supposedly lower
#  2 - the second version that is supposedly higher
#
IsDockerImageTagLower() {
  local checkedVersion="$1"
  local otherVersion="$2"
  
  # compare release versions
  if [ "${checkedVersion%%-*}" != "${otherVersion%%-*}" ]; then
  
    # compare major release version
    local checkedMajor="${checkedVersion%%.*}"
    local otherMajor="${otherVersion%%.*}"
    if [ $checkedMajor -lt $otherMajor ]; then
      exit 0
    fi
    
    # compare minor release version
    local checkedMinor=${checkedVersion#*.}
    checkedMinor=${checkedMinor%%.*}
    local otherMinor=${otherVersion#*.}
    otherMinor=${otherMinor%%.*}
    
    if [ $checkedMinor -lt $otherMinor ]; then
      exit 0
    fi
    
    # compare bugfix release version
    local checkedBugfix=${checkedVersion%%-*}
    checkedBugfix=${checkedBugfix##*.}
    local otherBugfix=${otherVersion%%-*}
    otherBugfix=${otherBugfix##*.}
    
    if [ $checkedBugfix -lt $otherBugfix ]; then
      exit 0
    fi
  
  # are the build versions and environments the same?
  elif [ "${checkedVersion##*-}" != "${otherVersion##*-}" ]; then
    local checkedEnv=$(echo "$checkedVersion" | grep -oP "(?<=-)[a-z]+")
    local otherEnv=$(echo "$otherVersion" | grep -oP "(?<=-)[a-z]+")
    
    # are build environments the same?
    if [ "$checkedEnv" = "$otherEnv" ]; then
      # compare build number
      local checkedBuildNumber=$(echo "$checkedVersion" | grep -oP "[0-9]+\$")
      local otherBuildNumber=$(echo "$otherVersion" | grep -oP "[0-9]+\$")
      
      if [ $checkedBuildNumber -lt $otherBuildNumber ]; then
        exit 0
      fi
    else
      # compare build environments
      if [ "$checkedEnv" = "test" ]; then
        exit 0
      elif [ "$checkedEnv" = "rc" ] && [ -z "$otherEnv" ]; then
        exit 0
      fi
    fi
  fi
  exit 1
}
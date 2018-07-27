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

# This script is being called by Bamboo Deployment Jobs.
# It creates a YAML file for a deployed service and pushes the file to the Kubernetes
# deployment repository. If a file with the same name already exists, only the Docker
# image tag inside the YAML file will be updated.
#
# Arguments:
#  1 - the new version (Docker tag) of the deployed service
#  2 - the minimum viable IP address of the deployed service
#  3 - the maximum viable IP address of the deployed service
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user


# treat unset variables as an error when substituting
set -u

# define global variables
DOCKER_REGISTRY="docker-registry.gerdi.research.lrz.de:5043"
KUBERNETES_REPOSITORY="https://code.gerdi-project.de/scm/sys/gerdireleases.git"
KUBERNETES_YAML_DIR="gerdireleases"
TEMPLATE_YAML="scripts/deployment/create-k8s-yaml/k8s_template.yml"

# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/misc-utils.sh
source ./scripts/helper-scripts/k8s-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Creates the YAML file for the service by copying a template and substituting
# placeholders.
#
# Arguments:
#  1 - the path to the file that is to be created
#  2 - the type of the service
#  3 - the name of the service
#  4 - the docker image name without tag
#  5 - the tag of the docker image
#  6 - a free IP address of a newly created YAML file
#  7 - the Atlassian user that will be added to the header of the YAML file
#
CreateYamlFile() {
  local kubernetesYaml="$1"
  local serviceType="$2"
  local serviceName="$3"
  local dockerImageName="$4"
  local dockerImageTag="$5"
  local clusterIp="$6"
  local userName="$7"
  
  if [ -z "$clusterIp" ]; then
    echo "Cannot create $kubernetesYaml: No free ClusterIP could be retrieved!" >&2
  fi
  
  # create directory if necessary
  local kubernetesDir="${kubernetesYaml%/*}"
  mkdir -p "$kubernetesDir"
    
  # copy template file
  cp "$TEMPLATE_YAML" "$kubernetesYaml"
  
  if [ ! -f "$kubernetesYaml" ]; then
    echo "The file $kubernetesYaml could not be created!" >&2
    exit 1
  fi  

  SubstitutePlaceholderInFile "$kubernetesYaml" "serviceName"
  SubstitutePlaceholderInFile "$kubernetesYaml" "serviceType"
  SubstitutePlaceholderInFile "$kubernetesYaml" "clusterIp"
  
  local dockerImage
  dockerImage="$dockerImageName:$dockerImageTag"
  SubstitutePlaceholderInFile "$kubernetesYaml" "dockerImage"
  
  local creationYear
  creationYear=$(date +'%Y')
  SubstitutePlaceholderInFile "$kubernetesYaml" "creationYear"
  
  local authorFullName
  authorFullName=$(curl -nsX GET https://tasks.gerdi-project.de/rest/api/2/user?username="$userName" \
                   | grep -oP "(?<=\"displayName\":\")[^\"]+")
  SubstitutePlaceholderInFile "$kubernetesYaml" "authorFullName"
  
  local environment
  environment=$(GetDeployEnvironmentName)
  SubstitutePlaceholderInFile "$kubernetesYaml" "environment"
  
  SubmitYamlFile "$kubernetesYaml" "Created '$kubernetesYaml' for Docker image '$dockerImageName:$dockerImageTag'."
}


# Updates an existing YAML file by changing the tag of the Docker
# image that is described therein.
#
# Arguments
#  1 - the path to the file that is to be created
#  2 - the type of the service
#  3 - the docker image name without tag
#  4 - the new tag of the docker image
#
UpdateYamlFile() {
  local kubernetesYaml="$1"
  local serviceType="$2"
  local dockerImageName="$3"
  local dockerImageTag="$4"
  
  perl -pi -e \
       "s~(.*?image: $dockerImageName)[^\s]*(.*)~\1:$dockerImageTag\2~" \
       "$kubernetesYaml"
  
  SubmitYamlFile "$kubernetesYaml" "Updated Docker image version of '$kubernetesYaml' to '$dockerImageTag'."
}


# Commits and pushes the updated or newly created YAML file to the Kubernetes repository.
#
# Arguments:
#  1 - the path to the YAML file that is to be pushed
#  2 - the commit message
#
SubmitYamlFile() {
  local kubernetesYaml="$1"
  local message="$2"
  
  local kubernetesSlug=$(echo "$KUBERNETES_REPOSITORY" | grep -oP '[^/]+(?=\.git)')

  (cd "$kubernetesSlug" && git add "${kubernetesYaml#*/}")
  (cd "$kubernetesSlug" && git commit -m "$message\n- This commit was triggered by a Bamboo Job.")
  (cd "$kubernetesSlug" && git push)
}


# Finds a free cluster IP in a range specified via Plan variables.
#
CreateClusterIp() {
  local minIP="$1"
  local maxIP="$2"
  
  if [ -z "$minIP" ] || [ -z "$maxIP" ]; then
    echo "You must pass three arguments to the script:\n 2: the minimum viable IP address of the deployed service\n 3: the maximum IP address" >&2
	exit 1
  fi
  
  local clusterIpPrefix
  clusterIpPrefix="${minIP%.*}."
  
  local clusterIpMin
  clusterIpMin="${minIP##*.}"
  
  local clusterIpMax
  clusterIpMax="${maxIP##*.}"
  
  if [ "$clusterIpMin" -lt 0 ] || [ "$clusterIpMin" -gt "$clusterIpMax" ]; then
    echo "$minIP is not a valid cluster IP! The last part must be smaller than the maximum ($clusterIpMax)!" >&2
    exit 1
  fi

  if [ "$clusterIpMax" -gt 255 ]; then
    echo "$maxIP is not a valid cluster IP!" >&2
    exit 1
  fi

  local clusterIp=$(GetFreeClusterIp "$KUBERNETES_YAML_DIR" "$clusterIpPrefix" "$clusterIpMin" "$clusterIpMax")

  if [ -z "$clusterIp" ]; then
    echo "Could not get ClusterIp: There must be at least one YAML file in $KUBERNETES_YAML_DIR!" >&2
    exit 1
  fi
  
  echo "$clusterIp"
}


# Retrieves the type of the service that is to be deployed.
#
# Arguments:
#  1 - the identifier of the project in which the repository exists
#
GetServiceType() {
  local projectId="$1"
  
  local projectName
  projectName=$(curl -nsX GET https://code.gerdi-project.de/rest/api/latest/projects/$projectId/ \
       | grep -oP "(?<=\"name\":\")[^\"]+" \
       | tr '[:upper:]' '[:lower:]')
     
  local serviceType
  if [ "$projectName" = "harvester" ]; then
    serviceType="harvest"
  else
    echo "Cannot create YAML file for repositories of project $projectName ($projectId)! You have to adapt the create-k8s-yaml.sh in order to support these projects!">&2
    exit 1
  fi
  
  echo "$serviceType"
}


# Assembles the name of the service to be deployed.
#
# Arguments:
#  1 - the slug of the repository of the deployed service
#  2 - the identifier of the project in which the repository exists
#
GetServiceName() {
  local repositorySlug="$1"
  local projectId="$2"
  
  local projectName
  projectName=$(curl -nsX GET https://code.gerdi-project.de/rest/api/latest/projects/$projectId/ \
       | grep -oP "(?<=\"name\":\")[^\"]+" \
       | tr '[:upper:]' '[:lower:]')
	   
  echo "$repositorySlug-$projectName"
}


# Checks out the Kubernetes deployment repository on a branch
# that fits the current deployment environment.
#
CheckoutKubernetesRepo() {
  local userName="$1"
  
  local branchName
  branchName=$(GetDeployEnvironmentBranch)
  
  local kubernetesSlug=$(echo "$KUBERNETES_REPOSITORY" | grep -oP '[^/]+(?=\.git)')

  # clone k8s deployments anew
  rm -rf "$kubernetesSlug"
  git clone -q "$KUBERNETES_REPOSITORY"
  
  # switch branch
  (cd "$kubernetesSlug" && git checkout "$branchName")
  
  # get user details
  local userProfile
  userProfile=$(curl -nsX GET https://tasks.gerdi-project.de/rest/api/2/user?username="$userName")
  
  local userFullName=$(echo "$userProfile" | grep -oP "(?<=\"displayName\":\")[^\"]+")
  local userEmail=$(echo "$userProfile" | grep -oP "(?<=\"emailAddress\":\")[^\"]+")
  
  # set user
  (cd "$kubernetesSlug" && git config user.name "$userFullName")
  (cd "$kubernetesSlug" && git config user.email "$userEmail")
}


# The main function to be executed in this script
#
Main() {
  local dockerImageTag="$1"
  if [ -z "$dockerImageTag" ]; then
    echo "You must pass the Docker image tag as first argument to the script!" >&2
	exit 1
  fi
  
  local minimumClusterIP="$2"
  local maximumClusterIP="$3"

  # get name of the user that ultimately triggered the deployment
  local atlassianUserName
  atlassianUserName=$(GetBambooUserName)
  
  # get the slug of the repository of the deployed service
  local repositorySlug
  repositorySlug=${bamboo_planRepository_1_repositoryUrl%.git}
  repositorySlug=${repositorySlug##*/}
  echo "Slug: '$repositorySlug'" >&2

  # get the project key of the repository of the deployed service
  local projectId
  projectId=${bamboo_planRepository_1_repositoryUrl%/*}
  projectId=${projectId##*/}

  # create a name for the deployed service
  local serviceType
  serviceType=$(GetServiceType "$projectId")
  echo "ServiceType: '$serviceType'" >&2

  # check out the Kubernetes deployment repository
  CheckoutKubernetesRepo "$atlassianUserName"
  
  local serviceName
  serviceName=$(GetServiceName "$repositorySlug" "$projectId")
  
  local kubernetesYaml
  kubernetesYaml="$KUBERNETES_YAML_DIR/$serviceType/$repositorySlug.yml"
  
  local dockerImageName
  dockerImageName="$DOCKER_REGISTRY/$serviceType/$repositorySlug"

  if [ -e "$kubernetesYaml" ]; then
    echo "The file $kubernetesYaml already exists, changing docker image version..." >&2
    UpdateYamlFile "$kubernetesYaml" "$serviceType" "$dockerImageName" "$dockerImageTag" 

  else
    local clusterIp
    clusterIp=$(CreateClusterIp "$minimumClusterIP" "$maximumClusterIP")
  
    echo "Creating file $kubernetesYaml..." >&2
    CreateYamlFile "$kubernetesYaml" "$serviceType" "$serviceName" "$dockerImageName" "$dockerImageTag" "$clusterIp" "$atlassianUserName"
  fi
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"

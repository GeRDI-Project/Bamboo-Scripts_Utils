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

# This script is being called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-ASTTE which aims
# to add a new service to the test environment.
#
# Arguments:
#  1 - the branch of gerdireleases in which the YAML file should be generated
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  gitCloneLink - the clone link of a git repository
#  clusterIpPrefix - the first three segments of the clusterIp of the deployed service (e.g. 192.168.0.)
#  clusterIpMin - the min value of the fourth IP segment [0...255]
#  clusterIpMax - the max value of the fourth IP segment [0...255]


# treat unset variables as an error when substituting
set -u

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
#  1 - the slug of the repository of the deployed service
#  2 - the type of the service
#  3 - the Atlassian user that will be associated with the JIRA ticket and 
#      the Bitbucket pull request
#  4 - the password for the Atlassian user
#
CreateYamlFile() {
  local repositorySlug="$1"
  local serviceType="$2"
  local userName="$3"
  local password="$4"
  
  local serviceName
  serviceName=$(GetServiceName "$repositorySlug" "$serviceType")
  
  # create directory if necessary
  local kubernetesDir
  kubernetesDir="gerdireleases/k8s-deployment/$serviceType"
  
  local kubernetesYaml
  kubernetesYaml="$kubernetesDir/$serviceName.yml"
  
  if [ ! -e "$kubernetesDir" ]; then
  	mkdir "$kubernetesDir"
    
  elif [ -e "$kubernetesYaml" ]; then
    echo "The file $kubernetesYaml already exists!" >&2
  	exit 1
  fi
    
  # copy template file
  cp "../scripts/plans/util/deploy-service/k8s_template.yml" "$kubernetesYaml"
  
  if [ ! -f "$kubernetesYaml" ]; then
    echo "The file $kubernetesYaml could not be created!" >&2
  	exit 1
  fi  

  SubstitutePlaceholderInFile "$kubernetesYaml" "serviceName"
  
  SubstitutePlaceholderInFile "$kubernetesYaml" "serviceType"
  
  local dockerImage
  dockerImage="docker-registry.gerdi.research.lrz.de:5043/$serviceType/$repositorySlug"
  SubstitutePlaceholderInFile "$kubernetesYaml" "dockerImage"
  
  local clusterIp
  clusterIp=$(CreateClusterIp)
  if [ -z "$clusterIp" ]; then
    exit 1
  fi
  SubstitutePlaceholderInFile "$kubernetesYaml" "clusterIp"
  
  local creationYear
  creationYear=$(date +'%Y')
  SubstitutePlaceholderInFile "$kubernetesYaml" "creationYear"
  
  local authorFullName
  authorFullName=$(GetAtlassianUserDisplayName "$userName" "$password" "$userName")
  SubstitutePlaceholderInFile "$kubernetesYaml" "authorFullName"
}


# Creates a JIRA ticket and a gerdireleases branch and pushes
# the YAML file to the branch. Subsequently, a pull request is sent out
# to the lead architects.
#
# Arguments:
#  1 - the slug of the repository of the deployed service
#  2 - the type of the service
#  3 - the branch to which the YAML file is to be merged
#  4 - the Atlassian user that will be associated with the JIRA ticket and 
#      the Bitbucket pull request
#  5 - the password for the Atlassian user
#
SubmitYamlFile() {
  local repositorySlug="$1"
  local serviceType="$2"
  local sourceBranch="$3"
  local userName="$4"
  local password="$5"
  
  cd gerdireleases
  
  local serviceName
  serviceName=$(GetServiceName "$repositorySlug" "$serviceType")
  
  local title="Deploy $serviceName"
  local description="Creates a Kubernetes YAML file for: $serviceName"
  
  local jiraKey
  jiraKey=$(CreateJiraTicket "$title" "$description" "$userName" "$password")
  
  if [ "$jiraKey" = "" ]; then
    echo "Could not Create JIRA Ticket!" >&2
	cd ..
    exit 1
  fi
  
  AddJiraTicketToCurrentSprint "$jiraKey" "$userName" "$password"
  StartJiraTask "$jiraKey" "$userName" "$password"

  local atlassianUserDisplayName
  atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$userName" "$password" "$userName")
  
  local atlassianUserEmail
  atlassianUserEmail=$(GetAtlassianUserEmailAddress "$userName" "$password" "$userName")

  local branchName
  branchName="$jiraKey-deploy-$serviceName"
  echo $(CreateBranch "$branchName") >&2
  echo $(PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "$jiraKey Created YAML file for Kubernetes") >&2

  echo $(CreatePullRequest \
        "$userName" \
        "$password" \
        "SYS" \
        "gerdireleases" \
        "$branchName" \
        "$sourceBranch" \
        "$jiraKey $title" \
        "$description" \
        "ntd@informatik.uni-kiel.de" \
        "di72jiv") >&2
  ReviewJiraTask "$jiraKey" "$userName" "$password"
  
  cd ..
  
  echo "$jiraKey"
}


# Finds a free cluster IP in a range specified via Plan variables.
#
CreateClusterIp() {
  local clusterIpPrefix
  clusterIpPrefix=$(GetValueOfPlanVariable "clusterIpPrefix")
  
  local clusterIpMin
  clusterIpMin=$(GetValueOfPlanVariable "clusterIpMin")
  
  local clusterIpMax
  clusterIpMax=$(GetValueOfPlanVariable "clusterIpMax")
  
  if [ "$clusterIpMin" -lt 0 ] || [ "$clusterIpMin" -gt "$clusterIpMax" ]; then
    echo "The plan variable 'clusterIpMin' must be a number in range [0..255] and smaller than 'clusterIpMax'!" >&2
    exit 1
  fi

  if [ "$clusterIpMax" -lt "$clusterIpMin" ] || [ "$clusterIpMax" -gt 255 ]; then
    echo "The plan variable 'clusterIpMax' must be a number in range [0..255] and greater than 'clusterIpMin'!" >&2
    exit 1
  fi

  local clusterIp=$(GetFreeClusterIp "gerdireleases/k8s-deployment" "$clusterIpPrefix" "$clusterIpMin" "$clusterIpMax")

  if [ -z "$clusterIp" ]; then
    echo "Could not get ClusterIp: There must be at least one YAML file in the k8s-deployment directory in gerdireleases!" >&2
    exit 1
  fi
  
  echo "$clusterIp"
}


# Assembles the name of the service to be deployed.
#
# Arguments:
#  1 - the git clone link of the source repository of the deployed service
#  2 - the Atlassian user name of a user who has access to the source repository
#  3 - the password of the Atlassian user
#
GetServiceType() {
  local gitCloneLink="$1"
  local userName="$2"
  local password="$3"

  local projectAbbrev
  projectAbbrev=$(GetProjectIdFromCloneLink "$gitCloneLink")
  
  local projectName
  projectName=$(GetBitBucketProjectName "$atlassianUserName" "$atlassianPassword" "$projectAbbrev")
  echo "Bitbucket Project: $projectName ($projectAbbrev)" >&2
  
  echo "$projectName" | tr '[:upper:]' '[:lower:]'
}


# Assembles the name of the service to be deployed.
#
# Arguments:
#  1 - the slug of the repository of the deployed service
#  2 - the type of the service
#
GetServiceName() {
  local repositorySlug="$1"
  local serviceType="$2"
  
  echo "$repositorySlug-$serviceType"
}


# The main function to be executed in this script
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "gitCloneLink"

  local tempFolder="addServiceToTestTemp"
  local environment="$1"

  local atlassianUserName
  atlassianUserName=$(GetBambooUserName)

  local atlassianPassword
  atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

  # retrieve plan variables
  local gitCloneLink
  gitCloneLink=$(GetValueOfPlanVariable "gitCloneLink")

  local repositorySlug
  repositorySlug=$(GetRepositorySlugFromCloneLink "$gitCloneLink")
  echo "Slug: '$repositorySlug'" >&2

  local serviceType
  serviceType=$(GetServiceType "$gitCloneLink" "$atlassianUserName" "$atlassianPassword")
  echo "ServiceType: '$serviceType'" >&2

  # clear, create and navigate to a temporary folder
  echo "Setting up a temporary folder" >&2
  rm -fr "$tempFolder"
  mkdir "$tempFolder"
  cd "$tempFolder"

  # check out gerdireleases repository
  mkdir gerdireleases
  cd gerdireleases
  $(CloneGitRepository "$atlassianUserName" "$atlassianPassword" "SYS" "gerdireleases") >&2
  git checkout "$environment"
  cd ..

  # create file
  CreateYamlFile "$repositorySlug" "$serviceType" "$atlassianUserName" "$atlassianPassword"

  # commit file
  local jiraKey
  jiraKey=$(SubmitYamlFile "$repositorySlug" "$serviceType" "$environment" "$atlassianUserName" "$atlassianPassword")

  echo "Removing the temporary directory" >&2
  cd ..
  rm -fr "$tempFolder"

  if [ -n "$jiraKey" ]; then
    echo "-------------------------------------------------" >&2
    echo "   FINISHED! PLEASE, CHECK THE JIRA TICKET:" >&2
    echo "https://tasks.gerdi-project.de/browse/$jiraKey" >&2
    echo "-------------------------------------------------" >&2
  fi
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"

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
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Creates the YAML file for the service by copying a template and substituting
# placeholders.
#
CreateYamlFile() {
  # create directory if necessary
  kubernetesDir="gerdireleases/k8s-deployment/$serviceType"
  kubernetesYaml="$kubernetesDir/$serviceName.yml"
  
  if [ ! -e "$kubernetesDir" ]; then
  	mkdir $kubernetesDir
    
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
  SubstitutePlaceholderInFile "$kubernetesYaml" "dockerImage"
  SubstitutePlaceholderInFile "$kubernetesYaml" "clusterIp"
  SubstitutePlaceholderInFile "$kubernetesYaml" "creationYear"
  SubstitutePlaceholderInFile "$kubernetesYaml" "authorFullName"
}


# Creates a JIRA ticket and a gerdireleases branch and pushes
# the YAML file to the branch. Subsequently, a pull request is sent out
# to the lead architects.
#
SubmitYamlFile() {
  cd gerdireleases
  
  title="Deploy $serviceName"
  description="Creates a Kubernetes YAML file for: $serviceName"
  
  jiraKey=$(CreateJiraTicket "$title" "$description" "$atlassianUserName" "$atlassianPassword")
  
  if [ "$jiraKey" = "" ]; then
    echo "Could not Create JIRA Ticket!" >&2
    exit 1
  fi
  
  AddJiraTicketToCurrentSprint "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  StartJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
    
  branchName="$jiraKey-deploy-$serviceName"
  echo $(CreateBranch "$branchName") >&2
  echo $(PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "$jiraKey Created YAML file for Kubernetes") >&2

  echo $(CreatePullRequest \
        "$atlassianUserName" \
        "$atlassianPassword" \
        "SYS" \
        "gerdireleases" \
        "$branchName" \
        "$environment" \
        "$jiraKey $title" \
        "$description" \
        "ntd@informatik.uni-kiel.de" \
        "di72jiv") >&2
  ReviewJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  
  cd ..
}


# Returns the first available clusterIp in a specified range by looking at clusterIPs of
# YAML files within the k8s-deployment folder.
#
# Arguments:
#  1 - the first three IP segments (e.g. "192.168.0.")
#  2 - the lowest viable fourth IP segment
#  3 - the highest viable fourth IP segment
#
GetFreeClusterIp() {
  ipPrefix="$1"
  rangeFrom=$2
  rangeTo=$3
  ipList=$(GetClusterIpList "gerdireleases/k8s-deployment")
  
  for ((lastSegment=$rangeFrom;lastSegment <= $rangeTo;lastSegment++))
  do
    clusterIp="$ipPrefix$lastSegment"
	
	if [ "$(echo "$ipList" | grep -oP "(?<![0-9])$clusterIp(?![0-9])")" = "" ]; then
      echo "$clusterIp"
	  exit 0
    fi
  done
  
  exit 1
}


# Returns a space-separated list of clusterIPs that are set in YAML files of the
# specified folder and sub-folders
#
# Arguments:
#  1 - the root folder path
#
GetClusterIpList() {
  serviceFolder="$1"
  ipList=""
    
  for file in "$serviceFolder"/*
  do
    if [ -d "$file" ]; then
      dirIpList=$(GetClusterIpList "$file")

      # if there is a clusterIP in a subfolder, check if it is higher than the current highest
      if [ "$dirIpList" != "" ]; then
        ipList="$ipList $dirIpList"
	  fi
    fi
  done
  
  while read file; do
    if [ -f "$serviceFolder/$file" ] && [ "${file##*.}" = "yml" ]; then
	    clusterIp=$(grep -oP "(?<=clusterIP:).+" "$serviceFolder/$file" | tr -d '[:space:]')
    fi
    
    # if there is a clusterIP, check if it is higher than the current highest
    if [ "$clusterIp" != "" ] && [ "$clusterIp" != "None" ]; then
        ipList="$ipList $clusterIp"
    fi
  done <<< "$(ls "$serviceFolder")"
  
  if [ "$ipList" != "" ]; then
    ipList="${ipList# }"
  fi
  echo "$ipList"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

# check early exit conditions
ExitIfNotLoggedIn
ExitIfPlanVariableIsMissing "atlassianPassword"
ExitIfPlanVariableIsMissing "gitCloneLink"

jiraKey=""
environment="$1"
atlassianUserName=$(GetBambooUserName)
atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

# test Atlassian credentials
ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
atlassianUserEmail=$(GetAtlassianUserEmailAddress "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")

echo "Current User: $atlassianUserName, $atlassianUserDisplayName, $atlassianUserEmail" >&2

# retrieve plan variables
gitCloneLink=$(GetValueOfPlanVariable "gitCloneLink")
clusterIpPrefix=$(GetValueOfPlanVariable "clusterIpPrefix")
clusterIpMin=$(GetValueOfPlanVariable "clusterIpMin")
clusterIpMax=$(GetValueOfPlanVariable "clusterIpMax")

if [ "$clusterIpMin" -lt 0 ] || [ "$clusterIpMin" -gt "$clusterIpMax" ]; then
  echo "The plan variable 'clusterIpMin' must be a number in range [0..255] and smaller than 'clusterIpMax'!" >&2
  exit 1
fi

if [ "$clusterIpMax" -lt "$clusterIpMin" ] || [ "$clusterIpMax" -gt 255 ]; then
  echo "The plan variable 'clusterIpMax' must be a number in range [0..255] and greater than 'clusterIpMin'!" >&2
  exit 1
fi

repositorySlug=$(GetRepositorySlugFromCloneLink "$gitCloneLink")
echo "Slug: '$repositorySlug'" >&2

projectAbbrev=$(GetProjectIdFromCloneLink "$gitCloneLink")
projectName=$(GetBitBucketProjectName "$atlassianUserName" "$atlassianPassword" "$projectAbbrev")
echo "Bitbucket Project: $projectName ($projectAbbrev)" >&2

# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder" >&2
rm -fr addServiceToTestTemp
mkdir addServiceToTestTemp
cd addServiceToTestTemp

mkdir gerdireleases
cd gerdireleases
$(CloneGitRepository "$atlassianUserName" "$atlassianPassword" "SYS" "gerdireleases") >&2
git checkout "$environment"
cd ..

# set up placeholder variables
serviceType=$(echo "$projectName" | tr '[:upper:]' '[:lower:]')
serviceName="$repositorySlug-$serviceType"
dockerImage="docker-registry.gerdi.research.lrz.de:5043/$serviceType/$repositorySlug"
creationYear=$(date +'%Y')
authorFullName="$atlassianUserDisplayName"
clusterIp=$(GetFreeClusterIp "$clusterIpPrefix" "$clusterIpMin" "$clusterIpMax")

if [ "$clusterIp" = "" ]; then
  echo "Could not get ClusterIp: There must be at least one YAML file in the k8s-deployment directory in gerdireleases!" >&2
  exit 1
fi

CreateYamlFile
SubmitYamlFile

echo "Removing the temporary directory" >&2
cd ..
rm -fr addServiceToTestTemp

if [ "$jiraKey" != "" ]; then
  echo "-------------------------------------------------" >&2
  echo "   FINISHED! PLEASE, CHECK THE JIRA TICKET:" >&2
  echo "https://tasks.gerdi-project.de/browse/$jiraKey" >&2
  echo "-------------------------------------------------" >&2
fi

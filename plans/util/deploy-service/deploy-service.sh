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


# Returns the next available ClusterIP by checking all yml files
# of the k8s-deployment folder of the gerdireleases repository
#
GetFreeClusterIp() {
  highestClusterIp=$(GetHighestClusterIp "gerdireleases/k8s-deployment")
  if [ "$highestClusterIp" = "" ]; then
    echo ""
  else
    echo "${highestClusterIp%.*}.$(expr ${highestClusterIp##*.} + 1)"
  fi  
}


# Iterates through a specified folder recursively, looking for yml-files
# and retrieving the highest clusterIP value.
#
GetHighestClusterIp() {
  serviceFolder="$1"
  highestClusterIp=""
    
  for file in "$serviceFolder"/*
  do
    if [ -d "$file" ]; then
      clusterIp=$(GetHighestClusterIp "$file")
      if [ "$clusterIp" != "" ] && [ "$clusterIp" \> "$highestClusterIp" ]; then
        highestClusterIp="$clusterIp"
	  fi
    fi
  done
  
  while read file; do
    if [ -f "$serviceFolder/$file" ] && [ "${file##*.}" = "yml" ]; then
	    clusterIp=$(grep -oP "(?<=clusterIP:).+" "$serviceFolder/$file" | tr -d '[:space:]')
    fi
	if [ "$clusterIp" != "" ] && [ "$clusterIp" != "None" ] && [ "$clusterIp" \> "$highestClusterIp" ]; then
      highestClusterIp="$clusterIp"
	fi
  done <<< "$(ls "$serviceFolder")"
  
  echo "$highestClusterIp"
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

echo "Current User: $atlassianUserDisplayName, $atlassianPassword, $atlassianUserEmail" >&2

# retrieve plan variables
gitCloneLink=$(GetValueOfPlanVariable gitCloneLink)

repositorySlug=$(GetRepositorySlugFromCloneLink "$gitCloneLink")
echo "Slug: '$repositorySlug'" >&2

# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder" >&2
rm -fr addServiceToTestTemp
mkdir addServiceToTestTemp
cd addServiceToTestTemp

projectAbbrev=$(GetProjectIdFromCloneLink "$gitCloneLink")
projectName=$(GetBitBucketProjectName "$atlassianUserName" "$atlassianPassword" "$projectAbbrev")
echo "Bitbucket Project: $projectName ($projectAbbrev)" >&2

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
clusterIp=$(GetFreeClusterIp)

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

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
source ./scripts/helper-scripts/misc-utils.sh

# check early exit conditions
ExitIfNotLoggedIn
ExitIfPlanVariableIsMissing "atlassianPassword"
ExitIfPlanVariableIsMissing "gitCloneLink"

atlassianUserName=$(GetBambooUserName)
atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

# test Atlassian credentials
ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

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
echo "Bitbucket Project: '$projectAbbrev'" >&2

# clone repository of the service that is to be added
CloneGitRepository "$atlassianUserName" "$atlassianPassword" "$projectAbbrev" "$repositorySlug"
cd "$repositorySlug"

  
if [ "$projectAbbrev" = "HAR" ]; then
  providerName=$()
  serviceName="$providerName-harvester"
  serviceType="harvest"
  dockerImage="docker-registry.gerdi.research.lrz.de:5043/harvest/$providerName"
else
  serviceType=$(GetBitBucketProjectName "$atlassianUserName" "$atlassianPassword" "$projectAbbrev" | tr '[:upper:]' '[:lower:]')
  
  echo "Unknown service '$projectAbbrev'!" >&2
  exit 1
fi

creationYear=$(date +'%Y')
authorFullName=$(GetAtlassianUserDisplayName "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
clusterIp=$(GetFreeClusterIp)

# add Kubernetes YAML file
cd
CloneGitRepository "$atlassianUserName" "$atlassianPassword" "SYS" "gerdireleases"

SubstitutePlaceholderInFile "$kubernetesYaml" "serviceName"
SubstitutePlaceholderInFile "$kubernetesYaml" "serviceType"
SubstitutePlaceholderInFile "$kubernetesYaml" "dockerImage"
SubstitutePlaceholderInFile "$kubernetesYaml" "clusterIp"
SubstitutePlaceholderInFile "$kubernetesYaml" "creationYear"
SubstitutePlaceholderInFile "$kubernetesYaml" "authorFullName"



# Returns the next available ClusterIP by checking all yml files
# of the k8s-deployment folder of the gerdireleases repository
#
GetFreeClusterIp() {
  highestClusterIp=$(GetHighestClusterIp "k8s-deployment")
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
	  if [ "$clusterIp" != "" ] && [ "$clusterIp" \> "$highestClusterIp" ]; then
      highestClusterIp="$clusterIp"
	  fi
  done <<< "$(ls "$serviceFolder")"
  
  echo "$highestClusterIp"
}







# retrieve name of the provider from the file name of the context listener
providerClassName=$(basename -s ContextListener.java src/main/java/de/gerdiproject/harvest/*ContextListener.java)
echo "Provider Class Name: '$providerClassName'" >&2

# check if Bamboo plans already exist and should be overridden
planKey="$( echo "$providerClassName" | sed -e "s~[a-z]~~g")HAR"
doPlansExist=$(IsUrlReachable "https://ci.gerdi-project.de/rest/api/latest/plan/CA-$planKey" "$atlassianUserName" "$atlassianPassword")

if [ "$doPlansExist" = true ]; then
  if [ "$overwriteFlag" = true ]; then
    echo "Overriding existing Bamboo jobs!" >&2
  else
    echo "Plans with the key '$planKey' already exist!" >&2
    exit 1
  fi
fi

# back up existing pom.xml
mv pom.xml backup-pom.xml

# create a setup pom.xml in cloned repository directory
CreateHarvesterSetupPom ""

# retrieve and unpack the harvester setup files
echo "Generating harvester setup files"
mvn generate-resources -Psetup
ExitIfLastOperationFailed "Could not generate Maven resources!"

# rename placeholders for the unpacked files
chmod o+rw scripts/renameSetup.sh
chmod +x scripts/renameSetup.sh
./scripts/renameSetup.sh\
 "$providerClassName"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"

# restore backed up pom.xml
mv -f backup-pom.xml pom.xml

# create Bamboo jobs
cd bamboo-specs
RunBambooSpecs "$atlassianUserName" "$atlassianPassword"

# clean up temporary folder
echo "Removing the temporary directory"
cd ..
rm -fr addServiceToTestTemp
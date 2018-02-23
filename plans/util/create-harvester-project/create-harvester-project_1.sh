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

# This script is being called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-CHP which creates
# a harvester project and Bamboo jobs:
#  1. Creates a Git repository in the harvester project (HAR)
#  2. Creates a pom derived from the latest version of the HarvesterSetup (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GeRDI-harvester-setup/)
#  3. Executes the setup, creating a bare minimum harvester project that has placeholders within files and file names
#  4. The placeholders are replaced by the plan variables of the Bamboo job (see below)
#  5. All files are formatted with AStyle
#  6. All files are committed and pushed to the remote Git repository.
#  7. Bamboo Plans and Deployment jobs for the project are created.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  providerName - the human readable name of the data provider that is to be harvested
#  providerUrl - the url to the data provider home page
#  authorOrganization - the organization of the harvester developer
#  authorOrganizationUrl - the url to the homepage of the harvester developer's organization
#  optionalAuthorName - the full name of the harvester developer, if not specified the executing user's name will be used
#  optionalAuthorEmail - the email address of the harvester developer, if not specified the executing user's email address will be used

source ./scripts/helper-scripts/atlassian-utils.sh
echo "source ./scripts failed? $?"
GetBambooUserName

source ./../../../helper-scripts/atlassian-utils.sh
echo "source ./../../../scripts failed? $?"
GetBambooUserName

(cd ../../../helper-scripts; ./atlassian-utils.sh)
echo "subshell failed? $?"
GetBambooUserName

(cd ../../../helper-scripts; source ./atlassian-utils.sh)
echo "subshell with source failed? $?"
GetBambooUserName

exit 0

# load helper scripts
./scripts/helper-scripts/atlassian-utils.sh
./scripts/helper-scripts/bamboo-utils.sh
./scripts/helper-scripts/git-utils.sh
./scripts/helper-scripts/maven-utils.sh
./scripts/helper-scripts/misc-utils.sh

# check early exit conditions
ExitIfNotLoggedIn
ExitIfPlanVariableIsMissing "atlassianPassword"
ExitIfPlanVariableIsMissing "providerName"
ExitIfPlanVariableIsMissing "providerUrl"
ExitIfPlanVariableIsMissing "authorOrganization"
ExitIfPlanVariableIsMissing "authorOrganizationUrl"

atlassianUserName=$(GetBambooUserName)
atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

# test Atlassian credentials
ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

# get details of bamboo user
atlassianUserEmail=$(GetAtlassianUserEmailAddress "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")

# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder" >&2
rm -fr harvesterSetupTemp
mkdir harvesterSetupTemp
cd harvesterSetupTemp

# create repository
repositorySlug=$(CreateGitRepository "$atlassianUserName" "$atlassianPassword" "HAR" "$providerName")
ExitIfLastOperationFailed

# clone newly created repository
CloneGitRepository "$atlassianUserName" "$atlassianPassword" "HAR" "$repositorySlug"

# create a setup pom.xml in cloned repository directory
cd $repositorySlug
CreateHarvesterSetupPom

# retrieve and unpack the harvester setup files
echo "Generating harvester setup files" >&2
mvn generate-resources -Psetup
ExitIfLastOperationFailed "Could not generate Maven resources!"

# get strings to replace placeholders
parentPomVersion=$(GetGerdiMavenVersion "GeRDI-parent-harvester")

providerName=$(GetValueOfPlanVariable providerName)
providerUrl=$(GetValueOfPlanVariable providerUrl)
authorOrganization=$(GetValueOfPlanVariable authorOrganization)
authorOrganizationUrl=$(GetValueOfPlanVariable authorOrganizationUrl)

authorFullName=$(GetValueOfPlanVariable optionalAuthorName)
if [ "$authorFullName" = "" ]; then
  authorFullName="$atlassianUserDisplayName"
fi

authorEmail=$(GetValueOfPlanVariable optionalAuthorEmail)
if [ "$authorEmail" = "" ]; then
  authorEmail="$atlassianUserEmail"
fi

# rename placeholders for the unpacked files
chmod o+rw scripts/renameSetup.sh
chmod +x scripts/renameSetup.sh
./scripts/renameSetup.sh\
 "$providerName"\
 "$providerUrl"\
 "$authorFullName"\
 "$authorEmail"\
 "$authorOrganization"\
 "$authorOrganizationUrl"\
 "$parentPomVersion"
 
providerClassName=$(ls src/main/java/de/gerdiproject/harvest/*ContextListener.java)
providerClassName=${providerClassName%ContextListener.java}
providerClassName=${providerClassName##*/}

# check if a plan with the same ID already exists in CodeAnalysis
planKey="$(echo "$providerClassName" | sed -e "s~[a-z]~~g")HAR"
doPlansExist=$(IsUrlReachable "https://ci.gerdi-project.de/rest/api/latest/plan/CA-$planKey" "$atlassianUserName" "$atlassianPassword")

if [ "$doPlansExist" = true ]; then
  echo "Plans with the key '$planKey' already exist!" >&2
  DeleteGitRepository "$atlassianUserName" "$atlassianPassword" "HAR" "$repositorySlug"
  exit 1
fi
 
# run AStyle without changing the files
echo "Formatting files with AStyle"
astyleResult=$(astyle --options="/usr/lib/astyle/file/kr.ini" --recursive --formatted "src/*")

# commit and push all files
PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "Bamboo: Created harvester repository for the provider '$bamboo_providerName'."

# create Bamboo jobs
cd bamboo-specs
CreateBambooSpecs "$atlassianUserName" "$atlassianPassword"

# clean up temporary folders
echo "Removing the temporary directory"
cd ../../
rm -fr harvesterSetupTemp
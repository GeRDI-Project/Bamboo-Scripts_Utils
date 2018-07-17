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

# This script is called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-CHP. It creates
# a harvester repository and Bamboo jobs:
#  1. Creates a Git repository in the harvester project (HAR)
#  2. Creates a pom derived from the latest version of the HarvesterSetup (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GeRDI-harvester-setup/)
#  3. Executes the setup, creating a bare minimum harvester project that has placeholders within files and file names
#  4. The placeholders are replaced by the plan variables of the Bamboo job (see below)
#  5. All files are formatted with AStyle
#  6. All files are committed and pushed to the remote Git repository.
#  7. Branches for staging and production environment are created and pushed.
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

# treat unset variables as an error when substituting
set -u


# define global constants
BITBUCKET_PROJECT="HAR"
TEMP_FOLDER="repoTemp"
  
  
# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Creates a Harvester repository with the current branch model and bamboo-agent permissions
# in Bitbucket.
#
CreateRepository() {
  local userName="$1"
  local password="$2"

  local repositorySlug
  repositorySlug=$(CreateGitRepository "$userName" "$password" "$BITBUCKET_PROJECT" "$providerName")
  
  ExitIfLastOperationFailed ""

  # grant the bamboo-agent the permission to tag the repository
  AddWritePermissionForRepository "$userName" "$password" "$BITBUCKET_PROJECT" "$repositorySlug" "bamboo-agent"

  # create temporary folder
  rm -fr "$TEMP_FOLDER"
  mkdir "$TEMP_FOLDER"
  cd "$TEMP_FOLDER"

  # clone newly created repository
  CloneGitRepository "$userName" "$password" "$BITBUCKET_PROJECT" "$repositorySlug"

  # copy placeholder project into the cloned repository
  echo $(cp -rT "../harvesterSetup/placeholderProject/" "./") >&2

  # get placeholder values
  local providerName
  providerName=$(GetValueOfPlanVariable providerName)
  
  local providerUrl
  providerUrl=$(GetValueOfPlanVariable providerUrl)

  # get name of author. if not present, use bamboo user name
  local atlassianUserDisplayName
  atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$userName" "$password" "$userName")
  
  local authorFullName
  authorFullName=$(GetValueOfPlanVariable optionalAuthorName)
  if [ -z "$authorFullName" ]; then
    authorFullName="$atlassianUserDisplayName"
  fi

  # get email address of author. if not present, use bamboo user email address
  local atlassianUserEmail
  atlassianUserEmail=$(GetAtlassianUserEmailAddress "$userName" "$password" "$userName")
  
  local authorEmail
  authorEmail=$(GetValueOfPlanVariable optionalAuthorEmail)
  if [ -z "$authorEmail" ]; then
    authorEmail="$atlassianUserEmail"
  fi
  
  local authorOrganization
  authorOrganization=$(GetValueOfPlanVariable authorOrganization)
  
  local authorOrganizationUrl
  authorOrganizationUrl=$(GetValueOfPlanVariable authorOrganizationUrl)
  
  local parentPomVersion
  parentPomVersion=$(GetLatestMavenVersion "GeRDI-parent-harvester" true)
  
  # rename placeholders for the project
  echo $(./../harvesterSetup/scripts/renameSetup.sh\
  "$providerName"\
  "$providerUrl"\
  "$authorFullName"\
  "$authorEmail"\
  "$authorOrganization"\
  "$authorOrganizationUrl"\
  "$parentPomVersion") >&2
 
  # run file formatter
  echo $(./scripts/formatting/astyle-format.sh) >&2

  # commit and push all files
  echo $(PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "Bamboo: Created harvester repository for the provider '$providerName'.") >&2

  # create branch model
  CreateBranch "stage"
  ExitIfLastOperationFailed ""
  CreateBranch "production"
  ExitIfLastOperationFailed ""

  cd ..
  
  echo "$repositorySlug"
}


# The main function of this script.
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "providerName"
  ExitIfPlanVariableIsMissing "providerUrl"
  ExitIfPlanVariableIsMissing "authorOrganization"
  ExitIfPlanVariableIsMissing "authorOrganizationUrl"
  
  local atlassianUserName
  atlassianUserName=$(GetBambooUserName)
  
  local atlassianPassword
  atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

  local repositorySlug
  repositorySlug=$(CreateRepository "$atlassianUserName" "$atlassianPassword")
 
  # retrieve name of the provider from the file name of the context listener
  local providerClassName
  providerClassName=$(basename -s ContextListener.java "$TEMP_FOLDER/src/main/java/de/gerdiproject/harvest/*ContextListener.java")

  # check if a plan with the same ID already exists in CodeAnalysis
  local planKey
  planKey="$(echo "$providerClassName" | sed -e "s~[a-z]~~g")$BITBUCKET_PROJECT"
  
  local doPlansExist
  doPlansExist=$(IsUrlReachable "https://ci.gerdi-project.de/rest/api/latest/plan/CA-$planKey" "$atlassianUserName" "$atlassianPassword")

  if [ "$doPlansExist" = true ]; then
    echo "Plans with the key '$planKey' already exist!" >&2
    DeleteGitRepository "$atlassianUserName" "$atlassianPassword" "$BITBUCKET_PROJECT" "$repositorySlug"
    exit 1
  fi
 
  # run Bamboo Specs
  ./scripts/plans/util/create-jobs-for-harvester/setup-bamboo-jobs.sh "$atlassianUserName" "$atlassianPassword" "$providerClassName" "$BITBUCKET_PROJECT" "$repositorySlug"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
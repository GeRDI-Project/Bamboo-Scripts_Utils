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

# This script attempts to upate all OAI-PMH harvesters on a specified branch to a specified version.
# If the specified version is lower than that of an OAI-PMH harvester, it is not updated.
#
# Arguments:
# 1 - (optional) the new version. If left empty, the last successful tag on the branch will be used
# 2 - (optional) the key of the JIRA update ticket. If left empty, a new ticket is to be created
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  version - the new Dockerfile base image version 
#  branch - the branch on which the versions are updated
#  reviewer - the user name of the person that has to review the pull requests
#
#  TEST_VERSION - the current version of the test environment
#  STAGING_VERSION - the current version of the staging environment
#  PRODUCTION_VERSION - the current version of the production environment

# treat unset variables as an error when substituting
set -u
  
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/docker-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Attempts to update all OAI-PMH harvesters, creating a JIRA ticket and
# a sub-task for every update, if applicable.
#
# Arguments
#  1 - the new Docker base image version
#  2 - the branch on which the update is to be deployed
#  3 - the reviewer of the pull-requests
#  4 - the Atlassian user name of the one performing the updates
#  5 - the Atlassian user password for the Atlassian user
#
UpdateAllOaiPmhHarvesters() {
  local newVersion="$1"
  local branch="$2"
  local reviewer="$3"
  local userName="$4"
  local password="$5"
  
  echo "Trying to update all OAI-PMH Harvesters to version $newVersion!" >&2
  
  local updateArguments
  updateArguments=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/HAR/repos \
  | python -m json.tool \
  | grep -oE '"http.*?git"' \
  | sed -e "s~\"http.*@code.gerdi-project.de/scm/\(.*\)/\(.*\)\.git\"~'$newVersion' '\\1' '\\2' '$branch' '$reviewer' '$userName' '$password'~")

  # execute update of all harvesters
  while read arguments
  do 
    eval TryOaiPmhRepositoryUpdate "$arguments"
  done <<< "$(echo -e "$updateArguments")"
}


# Attempts to update a single OAI-PMH harvester repository. If it
# is not a valid OAI-PMH harvester repository, or if the repository
# has a higher Docker base image version, the update is not executed.
#
# Arguments
#  1 - the new Docker base image version
#  2 - the project ID of the updated Bitbucket repository
#  3 - the slug of the updated Bitbucket repository
#  4 - the branch on which the update is to be deployed
#  5 - the reviewer of the pull-request
#  6 - the Atlassian user name of the one performing the updates
#  7 - the Atlassian user password for the Atlassian user
#
TryOaiPmhRepositoryUpdate() {
  local newVersion="$1"
  local projectId="$2"
  local slug="$3"
  local branch="$4"
  local reviewer="$5"
  local userName="$6"
  local password="$7"
  
  if ! $(IsOaiPmhHarvesterRepository "$projectId" "$slug" "$userName" "$password") ; then
    echo "Skipping $projectId/$slug, because it is not an OAI-PMH harvester." >&2
    exit 1
  fi
  
  local currentVersion=$(GetDockerBaseImageVersion "$projectId" "$slug" "$branch" "$userName" "$password")
  if $(IsDockerImageTagLower "$currentVersion" "$newVersion"); then
    UpdateOaiPmhRepository "$newVersion" "$projectId" "$slug" "$branch" "$reviewer" "$userName" "$password"
  else  
    echo "Skipping $projectId/$slug, because its current version, $currentVersion, is higher or equal to $newVersion!" >&2
  fi
}


# Updates a single OAI-PMH harvester repository, creating a JIRA-ticket
# if it does not exist already, and a JIRA sub-task.
# The repository is cloned, updated and subsequently pushed again.
#
# Arguments
#  1 - the new Docker base image version
#  2 - the project ID of the updated Bitbucket repository
#  3 - the slug of the updated Bitbucket repository
#  4 - the branch on which the update is to be deployed
#  5 - the reviewer of the pull-request
#  6 - the Atlassian user name of the one performing the updates
#  7 - the Atlassian user password for the Atlassian user
#
UpdateOaiPmhRepository() {
  local newVersion="$1"
  local projectId="$2"
  local slug="$3"
  local branch="$4"
  local reviewer="$5"
  local userName="$6"
  local password="$7"
  
  # create jira ticket
  if [ -z "$JIRA_KEY" ]; then
    JIRA_KEY=$(CreateJiraTicket \
	    "Update OAI-PMH Harvester Versions on $branch" \
        "The Docker base image versions of OAI-PMH Harvesters on their $branch branches are to be updated." \
        "$userName" \
        "$password")
    AddJiraTicketToCurrentSprint "$JIRA_KEY" "$userName" "$password"
    StartJiraTask "$JIRA_KEY" "$userName" "$password"
  fi
  
  # create jira sub-task
  local subTaskKey
  subTaskKey=$(CreateJiraSubTask \
	  "$JIRA_KEY" \
	  "Update OAI-PMH Harvester $projectId/$slug to Version $newVersion" \
      "The Docker base image version is updated to: $newVersion" \
	  "$userName" \
	  "$password")
  StartJiraTask "$subTaskKey" "$userName" "$password"
  
  # clone repository
  local tempDir="$slug"
  rm -rf "$tempDir"
  mkdir "$tempDir"
  (cd "$tempDir" && CloneGitRepository "$userName" "$password" "$projectId" "$slug")
  
  # switch branch
  if [ "$branch" != "master" ]; then
    (cd "$tempDir" && git checkout "$branchName")
  fi
  
  # create update branch
  local updateBranch
  updateBranch="versionUpdate/$JIRA_KEY-$subTaskKey-VersionUpdate"
  (cd "$tempDir" && CreateBranch "$updateBranch")
  
  # change version in Dockerfile
  perl -pi -e \
       "s~(.*?FROM docker-registry\.gerdi\.research\.lrz\.de:5043/harvest/oai-pmh:)[^\s]*(.*)~\1$newVersion\2~" \
       "$tempDir/Dockerfile"
  
  # commit and push changes
  local userDisplayName=$(GetAtlassianUserDisplayName "$userName" "$password")
  local userEmail=$(GetAtlassianUserEmailAddress "$userName" "$password")
  local message="Update Docker base image version to: $newVersion\n- This commit was triggered by a Bamboo Job."
  (cd "$tempDir" && PushAllFilesToGitRepository "$userDisplayName" "$userEmail" "$message")
  
  # clean up temp files
  rm -rf "$tempDir"
  
  # create pull-request
  (cd "$tempDir" && CreatePullRequest \
      "$userName" \
      "$password" \
      "$projectId" \
      "$slug" \
	  "$updateBranch" \
      "$branch" \
      "Update OAI-PMH Harvester $projectId/$slug" \
      "Docker base image version update." \
      "$reviewer" \
      "") >&2
	  
  # finish sub-task
  ReviewJiraTask "$subTaskKey" "$userName" "$password"
  FinishJiraTask "$subTaskKey" "$userName" "$password"
}


# This function attempts to retrieve the latest tagged version 
# of a specified Bitbucket repository.
#
# Arguments:
#  1 - the project ID of the Bitbucket repository
#  2 - the slug of the Bitbucket repository
#  3 - the branch that is checked
#
GetLatestTag() {
  local projectId="$1"
  local slug="$2"
  local branch="$3"
  
  # there is only one production version, so we can return it
  if [ "$branch" = "production" ]; then
    echo "$bamboo_PRODUCTION_VERSION"
	
  else
    # get the version from the latest Bitbucket tag
    local tagPrefix=""
    if [ "$branch" = "stage" ]; then
      tagPrefix="$bamboo_STAGING_VERSION-rc"
    else
      tagPrefix="$bamboo_TEST_VERSION-test"
    fi  

    curl -nsX GET "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$slug/tags/?filterText=$tagPrefix\&orderBy=modification" \
      | grep -oP '(?<="displayId":")'"$tagPrefix"'[^"]+'\
      | head -1
  fi
}


# The main function that is executed in this script
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "reviewer"
  ExitIfPlanVariableIsMissing "branch"

  local username
  username=$(GetBambooUserName)
  
  local password
  password=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$username" "$password"
  
  # check pull-request reviewer
  local reviewer
  reviewer=$(GetValueOfPlanVariable reviewer)
  echo "Reviewer: $reviewer" >&2
  if [ "$reviewer" = "$userName" ]; then
    echo "You cannot be a reviewer yourself! Please set the 'reviewer' variable to a proper value when running the plan customized!" >&2
    exit 1
  fi
  
  local branch
  branch=$(GetValueOfPlanVariable "branch")
  
  local newVersion
  newVersion="${1-}"
  
  if [ -z "$newVersion" ]; then
    newVersion=$(GetLatestTag "har" "oai-pmh" "$branch")
	
	if [ -z "$newVersion" ]; then
	  echo "Could not automatically retrieve a version to which the OAI-PMH harvesters are to be updated to!" >&2
	  exit 1
	fi
  fi
  
  # define global variables
  JIRA_KEY="${2-}"
  
  # update all OAI-PMH harvesters
  UpdateAllOaiPmhHarvesters "$newVersion" "$branch" "$reviewer" "$userName" "$password"

  echo " " >&2

  if [ -n "$JIRA_KEY" ]; then
    ReviewJiraTask "$JIRA_KEY" "$userName" "$password"
    echo "-------------------------------------------------" >&2
    echo "FINISHED UPDATING! PLEASE, CHECK THE JIRA TICKET:" >&2
    echo "https://tasks.gerdi-project.de/browse/$JIRA_KEY" >&2
    echo "-------------------------------------------------" >&2
  else
    echo "------------------------------" >&2
    echo "NO PROJECTS HAD TO BE UPDATED!" >&2
    echo "------------------------------" >&2
  fi

  echo " " >&2
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"

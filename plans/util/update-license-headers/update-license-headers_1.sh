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
 
# This script is called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-ULH.
# It iterates through all Harvester Projects and updates their license headers using the 'addLicenses' helper script
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  reviewer - the user name of the person that has to review the pull requests

# treat unset variables as an error when substituting
set -u

source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/bitbucket-utils.sh
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################


# This function updates all license headers of a specified harvester repository.
#
UpdateLicenseHeadersOfRepository() {
  local cloneLink="$1"
  local atlassianUserName="$2"
  local atlassianPassword="$3"

  local repositorySlug
  repositorySlug=$(GetRepositorySlugFromCloneLink "$cloneLink")
  
  local projectId
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")

  cd "$TOP_FOLDER"

  # remove and (re-)create a temporary folder
  rm -rf "$TEMP_FOLDER"
  TEMP_FOLDER=$(mktemp -d)
  cd "$TEMP_FOLDER"

  # clone repository
  CloneGitRepository "$atlassianUserName" "$atlassianPassword" "$projectId" "$repositorySlug"

  # check if a pom XML with the correct parent exists
  if [ ! -f "pom.xml" ]; then
    echo "Cannot update $projectId/$repositorySlug, because it is missing a pom.xml" >&2

  elif [ "$(GetPomValue "project.parent.artifactId" "")" != "GeRDI-parent-harvester" ]; then
    echo "Skipping $projectId/$repositorySlug, because the parent pom is not GeRDI-parent-harvester." >&2
	
  elif [ "$(GetPomValue "project.parent.version" "")" \< "6.2.0-SNAPSHOT" ]; then
    echo "Cannot update $projectId/$repositorySlug. The parent pom must be 'GeRDI-parent-harvester' of version '6.2.0-SNAPSHOT' or higher!" >&2

  else
    # generate maven resources
    mvn generate-resources

    # execute script for updating license headers
    $(./scripts/addLicenses.sh)

    # continue if the script was successful
    if [ $? -eq 0 ]; then
      PushLicenseHeaderUpdate "$projectId" "$repositorySlug" "$atlassianUserName" "$atlassianPassword"
	else
	  echo "Could not add license headers to $projectId/$repositorySlug!" >&2
    fi
  fi
}


# This function commits and pushes updated license headers of a specified repository.
#
PushLicenseHeaderUpdate() { 
  local projectId="$1" 
  local repositorySlug="$2"
  local atlassianUserName="$3"
  local atlassianPassword="$4"
  
  if [ $(GetNumberOfUnstagedChanges) -ne 0 ]; then
    echo "License headers of $projectId/$repositorySlug need to be updated!" >&2
	
	# create JIRA ticket, if needed
	if [ -z "$JIRA_KEY" ]; then 
 	  JIRA_KEY=""$(CreateJiraTicket \
	    "Update Harvester License Headers" \
        "The license headers of some harvester projects are to be updated." \
        "$atlassianUserName" \
        "$atlassianPassword")
      AddJiraTicketToCurrentSprint "$JIRA_KEY" "$atlassianUserName" "$atlassianPassword"
      StartJiraTask "$JIRA_KEY" "$atlassianUserName" "$atlassianPassword"
    fi
	
    # create sub-task
	local subTaskKey
    subTaskKey=$(CreateJiraSubTask \
	  "$JIRA_KEY" \
	  "Add license headers to $projectId/$repositorySlug" \
      "The license headers of $repositorySlug need to be updated and/or added." \
	  "$atlassianUserName" \
	  "$atlassianPassword")
	  
	# start sub-task
    StartJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
  
    # create git branch
	local branchName
    branchName="$JIRA_KEY-$subTaskKey-UpdateLicenseHeaders"
	CreateGitBranch "$branchName"
    
	# commit and push updates
	local commitMessage
    commitMessage="$JIRA_KEY $subTaskKey Updated license headers."
	
	local atlassianUserEmail
    atlassianUserEmail=$(GetAtlassianUserEmailAddress "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
	
	local atlassianUserDisplayName
    atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
	
	echo $(PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "$commitMessage") >&2
  
    local reviewer
    reviewer=$(GetValueOfPlanVariable reviewer)
	
    # create pull request
    echo $(CreatePullRequest \
        "$atlassianUserName" \
        "$atlassianPassword" \
        "$projectId" \
        "$repositorySlug" \
	    "$branchName" \
        "master" \
        "$repositorySlug Update License Headers" \
        "Updated and/or added license headers." \
        "$reviewer" \
        "") >&2
      ReviewJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
      FinishJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
  else
    echo "All headers of $projectId/$repositorySlug are up-to-date!" >&2
  fi
}


# The main function that is executed in this script.
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "reviewer"

  local atlassianUserName
  atlassianUserName=$(GetBambooUserName)

  local atlassianPassword
  atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

  # check pull-request reviewer
  local reviewer=$(GetValueOfPlanVariable reviewer)
  echo "Reviewer: $reviewer" >&2
  if [ "$reviewer" = "$atlassianUserName" ]; then
    echo "You cannot be a reviewer yourself! Please set the 'reviewer' variable to a proper value when running the plan customized!" >&2
    exit 1
  fi
    
  # init global variables
  TOP_FOLDER="$PWD"
  TEMP_FOLDER=""
  JIRA_KEY=""

  # fire in the hole!
  local repositoryArguments="'$atlassianUserName' '$atlassianPassword'"
  ProcessRepositoriesOfProject \
    "$atlassianUserName" \
    "$atlassianPassword" \
    "HAR" \
    "UpdateLicenseHeadersOfRepository" \
    "$repositoryArguments"

  echo " " >&2

  if [ -n "$JIRA_KEY" ]; then
    ReviewJiraTask "$JIRA_KEY" "$atlassianUserName" "$atlassianPassword"
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
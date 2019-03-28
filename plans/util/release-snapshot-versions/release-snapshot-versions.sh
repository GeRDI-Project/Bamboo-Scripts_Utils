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
 
# This script removes all "-SNAPSHOT" suffixes within all pom.xmls of specified
# repositories.
#
# Arguments:
#  1 - a comma separated list of clone links and BitBucket project IDs
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  jiraIssueKey - (optional) the key of a ticket of which sub-tasks are to be created for each repository

# treat unset variables as an error when substituting
set -u

# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################


# Clones a repository, removes all -SNAPSHOT suffixes from the main pom.xml,
# creates a pull request and a sub-task of the main JIRA ticket.
#
# Arguments
#  1 - the git clone link of the repository
#  2 - the username of the Atlassian user that triggered the Bamboo job
#  3 - the password of the Atlassian user that triggered the Bamboo job
#  4 - the key of the main JIRA task that describes the snapshot removal process
#  5 - the username of the reviewer of all created pull requests
#  6 - the email address of the Atlassian user that triggered the Bamboo job
#  7 - the full name of the Atlassian user that triggered the Bamboo job
#
RemoveSnapshotsOfRepository() {
  local cloneLink="$1"
  local atlassianUserName="$2"
  local atlassianPassword="$3"
  local jiraKey="$4"
  local reviewer="$5"
  local atlassianUserEmail="$6"
  local atlassianUserDisplayName="$7"
  
  local projectId
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")
  
  local slug
  slug=$(GetRepositorySlugFromCloneLink "$cloneLink")  
  
  if ! $(IsMavenizedRepository "$projectId" "$slug" "$atlassianUserName" "$atlassianPassword") ; then
	echo "Skipping '$projectId/$slug', because it does not have a pom.xml!" >&2
	
  else
    # create sub-task
    local subTaskKey
    subTaskKey=$(CreateJiraSubTask \
      "$jiraKey" \
      "Remove Snapshots of $projectId/$slug" \
      "Remove all -SNAPSHOT version suffixes from the pom.xml." \
      "$atlassianUserName" \
      "$atlassianPassword")
	
	# start sub-task
    StartJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
	
    # clone repository
	mkdir "$slug"
    (cd "$slug" && CloneGitRepository "$atlassianUserName" "$atlassianPassword" "$projectId" "$slug")
	  
    # create branch
    local branch="$subTaskKey-RemoveSnapshots"
    (cd "$slug" && CreateBranch "$branch")
  
    # remove snapshot versions from pom
    UpdateMavenSnapshotToRelease "$slug" false >&2
  
    # commit and push pom changes
    (cd "$slug" && PushAllFilesToGitRepository \
      "$atlassianUserDisplayName" \
      "$atlassianUserEmail" \
      "$jiraKey $subTaskKey Removed SNAPSHOT versions from pom.xml") >&2
	
	# review sub-task
    ReviewJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"

    # create pull request
    local feedback
	feedback=$(CreatePullRequest \
      "$atlassianUserName" \
      "$atlassianPassword" \
      "$projectId" \
      "$slug" \
      "$branch" \
      "master" \
      "Remove Snapshots of $projectId/$slug" \
      "All Snapshots should be removed." \
      "$reviewer" \
      "")
      
    # clean up temporary folder
    rm -rf "$slug"
  fi
}


# The main function to be called by this script.
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn

  # get list of projects and repositories
  local projectsAndCloneLinks="$1"
  if [ -z "$projectsAndCloneLinks" ]; then
    echo "You need to pass a list of repositories to update as the first argument of the script!" >&2
    exit 1
  fi
  
  # get pull-request reviewer
  ExitIfPlanVariableIsMissing "reviewer"
  local reviewer=$(GetValueOfPlanVariable "reviewer")
  
  # get and verify credentials
  local atlassianUserName=$(GetBambooUserName)
  
  ExitIfPlanVariableIsMissing "atlassianPassword"
  local atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")
  
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"
  
  # get more Atlassian user details
  local atlassianUserEmail=$(GetAtlassianUserEmailAddress "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
  local atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
  
  # retrieve the key of a JIRA ticket
  local jiraKey=$(GetValueOfPlanVariable "jiraIssueKey")
  
  # create JIRA ticket if none exists yet
  if [ -z "jiraKey" ]; then
    jiraKey=$(CreateJiraTicket \
  	    "Remove Snapshot Versions for Release $bamboo_TEST_VERSION" \
          "The -SNAPSHOT suffixes from all projects' pom.xmls are to be removed in order to be able to submit to Maven Central." \
          "$atlassianUserName" \
          "$atlassianPassword")
  fi
		
  # start JIRA ticket in the current sprint
  AddJiraTicketToCurrentSprint "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  StartJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  
  # process all repositories
  local repositoryArguments="'$atlassianUserName' '$atlassianPassword' '$jiraKey' '$reviewer' '$atlassianUserEmail' '$atlassianUserDisplayName'"
  ProcessListOfProjectsAndRepositories \
    "$atlassianUserName" \
    "$atlassianPassword" \
    "$projectsAndCloneLinks" \
    "RemoveSnapshotsOfRepository" \
    "$repositoryArguments"

  # review JIRA task
  ReviewJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"

  # final log
  echo " " >&2
  echo "-------------------------------------------------------------------" >&2
  echo "FINISHED REMOVING SNAPSHOT SUFFIXES! PLEASE, CHECK THE JIRA TICKET:" >&2
  echo "https://tasks.gerdi-project.de/browse/$jiraKey" >&2
  echo "-------------------------------------------------------------------" >&2
  echo " " >&2
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
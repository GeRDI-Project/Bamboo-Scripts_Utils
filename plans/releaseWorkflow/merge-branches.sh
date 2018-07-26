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
 
# This script iterates a list of projects and/or git clone links and merges one
# branch to another.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  projectsAndCloneLinks - a comma separated list of project abbreviations and clone links for which branches are to be created
#  createdBranchName - the name of the branch that is to be created
#  sourceBranchName - the name of the source branch from which the branch is to be created
#  title - the title of the pull request and JIRA ticket
#  description - the description of the pull request and JIRA ticket
#  reviewer - the reviewer for the pull request

# treat unset variables as an error when substituting
set -u
  
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Creates a pull request for merging a source branch to a target branch of a specified repository.
#
# Arguments:
#  1 - the git clone link of the repository
#  2 - the Atlassian user that merges the branches
#  3 - the password for the atlassian user
#  4 - the name of the branch that is to be merged to the target branch
#  5 - the name of the branch to which the source branch is merged
#  6 - the title of the pull request
#  7 - the description of the pull request
#  8 - a pull request reviewer
#
MergeBranchesOfRepository() {
  local cloneLink="$1"
  local userName="$2"
  local password="$3"
  local sourceBranch="$4"
  local targetBranch="$5"
  local title="$6"
  local description="$7"
  local reviewer="$8"
  
  local projectId
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")
  
  local slug
  slug=$(GetRepositorySlugFromCloneLink "$cloneLink")  
  
  # abort if source branch does not exist
  if ! $(HasBitbucketBranch "$userName" "$password" "$projectId" "$slug" "$sourceBranch"); then
    echo "Cannot merge '$sourceBranch' to '$targetBranch' in '$projectId/$slug', because '$sourceBranch' does not exist." >&2
    cd ..
    rm -rf "$slug"
	exit 1
  fi
  
  # abort if target branch does not exist
  if ! $(HasBitbucketBranch "$userName" "$password" "$projectId" "$slug" "$targetBranch"); then
    echo "Cannot merge '$sourceBranch' to '$targetBranch' in '$projectId/$slug', because '$targetBranch' does not exist." >&2
    cd ..
    rm -rf "$slug"
    exit 1
  fi
  
  # create pull request
  CreatePullRequest \
    "$userName" \
	"$password" \
	"$projectId" \
	"$slug" \
	"$sourceBranch" \
	"$targetBranch" \
	"$title" \
	"$description" \
	"$reviewer" \
	""
}

   
# Main function that is executed by this script
#
Main() {
  local atlassianUserName="$1"
  local atlassianPassword="$2"
  local sourceBranch="$3"
  local targetBranch="$4"
  local projectsAndCloneLinks="$5"
  local title="$6"
  local description="$7"
  local reviewer="$8"
  
  # create JIRA ticket
  jiraKey=$(CreateJiraTicket \
	    "$title" \
        "$description" \
        "$atlassianUserName" \
        "$atlassianPassword")
		
  # start JIRA ticket in the current sprint
  AddJiraTicketToCurrentSprint "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  StartJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  
  # define a list of arguments to be used by the 'MergeBranchesOfRepository' function
  local repositoryArguments="'$atlassianUserName' '$atlassianPassword' '$sourceBranch' '$targetBranch' '$jiraKey $title' '$description' '$reviewer'"
  
  ProcessListOfProjectsAndRepositories \
    "$atlassianUserName" \
    "$atlassianPassword" \
    "$projectsAndCloneLinks" \
    "MergeBranchesOfRepository" \
    "$repositoryArguments"  
  
  # review JIRA ticket
  ReviewJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  
  if [ -n "$jiraKey" ]; then
    echo "-------------------------------------------------" >&2
    echo "Created Pull-requests: stage -> production" >&2
    echo "https://tasks.gerdi-project.de/browse/$jiraKey" >&2
    echo "-------------------------------------------------" >&2
  fi
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"


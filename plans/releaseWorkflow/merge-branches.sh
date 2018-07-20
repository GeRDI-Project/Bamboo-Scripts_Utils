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
#  2 - the name of the branch that is to be merged to the target branch
#  3 - the name of the branch to which the source branch is merged
#  4 - the title of the pull request
#  5 - the description of the pull request
#  6 - a pull request reviewer
#
MergeBranchesOfRepository() {
  local cloneLink="$1"
  local sourceBranch="$2"
  local targetBranch="$3"
  local title="$4"
  local description="$5"
  local reviewer="$6"
  
  local projectId
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")
  
  local slug
  slug=$(GetRepositorySlugFromCloneLink "$cloneLink")  
  
  # abort if source branch does not exist
  if ! $(HasBitbucketBranch "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" "$projectId" "$slug" "$sourceBranch"); then
    echo "Cannot merge '$sourceBranch' to '$targetBranch' in '$projectId/$slug', because '$sourceBranch' does not exist." >&2
    cd ..
    rm -rf "$slug"
	exit 1
  fi
  
  # abort if target branch does not exist
  if ! $(HasBitbucketBranch "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" "$projectId" "$slug" "$targetBranch"); then
    echo "Cannot merge '$sourceBranch' to '$targetBranch' in '$projectId/$slug', because '$targetBranch' does not exist." >&2
    cd ..
    rm -rf "$slug"
    exit 1
  fi
  
  # create pull request
  CreatePullRequest \
    "$ATLASSIAN_USER_NAME" \
	"$ATLASSIAN_PASSWORD" \
	"$projectId" \
	"$slug" \
	"$sourceBranch" \
	"$targetBranch" \
	"$title" \
	"$description" \
	"$reviewer" \
	""
}


# Merges a source branch to a target branch of each repository of a Bitbucket project.
#
# Arguments:
#  1 - the bitbucket project abbreviation
#  2 - the name of the branch that is to be merged to the target branch
#  3 - the name of the branch to which the source branch is merged
#  4 - the title of the pull request
#  5 - the description of the pull request
#  6 - a pull request reviewer
#
MergeBranchesOfProject() {
  local projectId="$1"
  local sourceBranch="$2"
  local targetBranch="$3"
  local title="$4"
  local description="$5"
  local reviewer="$6"
  
  local repoUrls
  repoUrls=$(curl -sX GET -u "$ATLASSIAN_USER_NAME:$ATLASSIAN_PASSWORD" "https://code.gerdi-project.de/rest/api/latest/projects/$projectId/repos" \
             | python -m json.tool \
             | grep -oP '(?<=")http.*?git(?=")') 

  # execute update of all repositories
  echo "Updating all repositories of project '$projectId':" >&2
  while read cloneLink
  do 
    $(MergeBranchesOfRepository "$cloneLink" "$sourceBranch" "$targetBranch" "$title" "$description" "$reviewer")
  done <<< "$(echo -e "$repoUrls")"
  
  exit 0
}


# Processes an argument and checks if it is a git clone link or a project ID,
# in order to update either a single repository, or an entire project.
#
# Arguments:
#  1 - either a Bitbucket Project key or a git clone link
#  2 - the name of the branch that is to be merged to the target branch
#  3 - the name of the branch to which the source branch is merged
#  4 - the title of the pull request
#  5 - the description of the pull request
#  6 - a pull request reviewer
#
MergeBranchesOfArgument() {
  local argument="$1"
  local sourceBranch="$2"
  local targetBranch="$3"
  local title="$4"
  local description="$5"
  local reviewer="$6"

  if $(IsProject "$argument"); then
    echo $(MergeBranchesOfProject "$argument" "$sourceBranch" "$targetBranch" "$title" "$description" "$reviewer") >&2
	
  elif $(IsCloneLink "$argument"); then
    echo $(MergeBranchesOfRepository "$argument" "$sourceBranch" "$targetBranch" "$title" "$description" "$reviewer") >&2

  else
    echo "Argument '$argument' is neither a valid git clone link, nor a BitBucket project!" >&2
  fi
}


# Returns true if the argument is a git clone link.
#
# Arguments:
#  1 - the argument that is to be tested
#
IsCloneLink() {
  local checkedArg="$1"
  
  if $(echo "$checkedArg" | grep -qx "https:.*\.git"); then
    local projectId
	projectId=$(GetProjectIdFromCloneLink "$checkedArg")
	
	local slug
    slug=$(GetRepositorySlugFromCloneLink "$checkedArg")
	
    IsUrlReachable "https://code.gerdi-project.de/rest/api/latest/projects/$projectId/repos/$slug" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
  else
    exit 1
  fi
}


# Returns true if the argument is a project.
#
# Arguments:
#  1 - the argument that is to be tested
#
IsProject() {
  local checkedArg="$1"
  
  if $(echo "$checkedArg" | grep -qxP "[A-Za-z]+"); then
    IsUrlReachable "https://code.gerdi-project.de/rest/api/latest/projects/$checkedArg/" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
  else
    exit 1
  fi
}

   
# Main function that is executed by this script
#
Main() {
  ATLASSIAN_USER_NAME="$1"
  ATLASSIAN_PASSWORD="$2"
  local sourceBranch="$3"
  local targetBranch="$4"
  local projectsAndCloneLinks=$(echo "$5" | tr -d " " | tr "," "\n")
  local title="$6"
  local description="$7"
  local reviewer="$8"
  
  # create JIRA ticket
  jiraKey=$(CreateJiraTicket \
	    "$title" \
        "$description" \
        "$ATLASSIAN_USER_NAME" \
        "$ATLASSIAN_PASSWORD")
		
  AddJiraTicketToCurrentSprint "$jiraKey" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
  StartJiraTask "$jiraKey" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"

  # iterate through all clone links and/or projects
  while read projectOrCloneLink
  do 
    $(MergeBranchesOfArgument "$projectOrCloneLink" "$sourceBranch" "$targetBranch" "$jiraKey $title" "$description" "$reviewer")
  done <<< "$(echo -e "$projectsAndCloneLinks")"
  
  ReviewJiraTask "$jiraKey" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"


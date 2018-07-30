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
 
# This script is called by a Bamboo Job. It iterates a list of projects and/or git clone links and creates
# a branch of a specified name from a specified source branch.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  projectsAndCloneLinks - a comma separated list of project abbreviations and clone links for which branches are to be created
#  createdBranchName - the name of the branch that is to be created
#  sourceBranchName - the name of the source branch from which the branch is to be created

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

# Adds a new branch to a repository.
#
# Arguments:
#  1 - the git clone link of the repository
#  2 - the name of the source branch from which the branch is to be created
#  3 - the name of the branch that is to be created
#
UpdateBranchesOfRepository() {
  local cloneLink="$1"
  local sourceBranchName="$2"
  local createdBranchName="$3"
  
  local projectId
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")
  
  local slug
  slug=$(GetRepositorySlugFromCloneLink "$cloneLink")
  
  # create temp directory
  mkdir "$slug"
  cd "$slug"
  
  # clone repository
  $(CloneGitRepository "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" "$projectId" "$slug")
  
  # abort if target branch already exists
  if $(git branch -a | grep -qx " *remotes/origin/$createdBranchName"); then
    echo "Repository '$projectId/$slug' already has a '$createdBranchName' branch." >&2
    cd ..
    rm -rf "$slug"
    exit 1
  fi
  
  # abort if source branch does not exist
  if ! $(git branch -a | grep -qx " *remotes/origin/$sourceBranchName"); then
    echo "Branch '$createdBranchName' cannot be created for repository '$projectId/$slug', because the source branch '$sourceBranchName' does not exist!" >&2
    cd ..
    rm -rf "$slug"
	exit 1
  fi
  
  # create new branch from source branch
  echo $(git checkout "$sourceBranchName") >&2
  CreateBranch "$createdBranchName"
  
  # remove temp directory
  cd ..
  rm -rf "$slug"
}


# Adds a new branch to each repository of a bitbucket project.
#
# Arguments:
#  1 - the bitbucket project abbreviation
#  2 - the name of the source branch from which the branch is to be created
#  3 - the name of the branch that is to be created
#
UpdateBranchesOfProject() {
  local projectId="$1"
  local sourceBranchName="$2"
  local createdBranchName="$3"
  
  local repoUrls
  repoUrls=$(curl -sX GET -u "$ATLASSIAN_USER_NAME:$ATLASSIAN_PASSWORD" "https://code.gerdi-project.de/rest/api/latest/projects/$projectId/repos" | python -m json.tool | grep -oP '(?<=")http.*?git(?=")') 

  # execute update of all repositories
  echo "Updating all repositories of project '$projectId':" >&2
  while read cloneLink
  do 
    $(UpdateBranchesOfRepository "$cloneLink" "$sourceBranchName" "$createdBranchName")
  done <<< "$(echo -e "$repoUrls")"
  
  exit 0
}


# Processes an argument and checks if it is a git clone link or a project ID,
# in order to update either a single branch, or an entire project.
#
# Arguments:
#  1 - either a Bitbucket Project key or a git clone link
#  2 - the name of the source branch from which the branch is to be created
#  3 - the name of the branch that is to be created
#
UpdateBranchesOfArgument() {
  local argument="$1"
  local sourceBranchName="$2"
  local createdBranchName="$3"

  if $(IsProject "$argument" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"); then
    echo $(UpdateBranchesOfProject "$argument" "$sourceBranchName" "$createdBranchName") >&2
	
  elif $(IsCloneLink "$argument" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"); then
    echo $(UpdateBranchesOfRepository "$argument" "$sourceBranchName" "$createdBranchName") >&2

  else
    echo "Argument '$argument' is neither a valid git clone link, nor a BitBucket project!" >&2
  fi
}


# Main function that is executed by this script
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "projectsAndCloneLinks"
  ExitIfPlanVariableIsMissing "createdBranchName"
  ExitIfPlanVariableIsMissing "sourceBranchName"

  ATLASSIAN_USER_NAME=$(GetBambooUserName)
  ATLASSIAN_PASSWORD=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"

  # get plan variables
  local createdBranchName
  createdBranchName=$(GetValueOfPlanVariable createdBranchName)
  
  local sourceBranchName
  sourceBranchName=$(GetValueOfPlanVariable sourceBranchName)
  
  local projectsAndCloneLinks
  projectsAndCloneLinks=$(GetValueOfPlanVariable "projectsAndCloneLinks" | tr -d " " | tr "," "\n")

  # iterate through all clone links and/or projects
  while read projectOrCloneLink
  do 
    $(UpdateBranchesOfArgument "$projectOrCloneLink" "$sourceBranchName" "$createdBranchName")
  done <<< "$(echo -e "$projectsAndCloneLinks")"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"


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
 
# This script is being called by a Bamboo Job. It iterates a list of projects and/or git clone links and creates
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
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Adds a new branch to a repository.
#
# Arguments:
#  1 - the git clone link of the repository
#
UpdateBranchesOfRepository() {
  cloneLink="$1"
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")
  slug=$(GetRepositorySlugFromCloneLink "$cloneLink")
  
  # create temp directory
  mkdir "$slug"
  cd "$slug"
  
  # clone repository
  $(CloneGitRepository "$atlassianUserName" "$atlassianPassword" "$projectId" "$slug")
  
  # abort if branch exists
  hasBranch=$(git branch -a | grep -cx " *remotes/origin/$createdBranchName")
  if [ "$hasBranch" = "1" ]; then
    echo "Repository '$projectId/$slug' already has a '$createdBranchName' branch." >&2
    cd ..
    rm -rf "$slug"
    exit 1
  fi
  
  # abort if source branch does not exist
  hasBranch=$(git branch -a | grep -cx " *remotes/origin/$sourceBranchName")
  if [ "$hasBranch" = "0" ]; then
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
  exit 0
}


# Adds production branches to all repositories of a bitbucket project.
#
# Arguments:
#  1 - the bitbucket project abbreviation
#
UpdateBranchesOfProject() {
  projectId="$1"
  
  repoUrls=$(curl -sX GET -u "$atlassianUserName:$atlassianPassword" "https://code.gerdi-project.de/rest/api/latest/projects/$projectId/repos" | python -m json.tool | grep -oP '(?<=")http.*?git(?=")') 

  # execute update of all repositories
  echo "Updating all repositories of project '$projectId':" >&2
  while read cloneLink
  do 
    $(UpdateBranchesOfRepository "$cloneLink")
  done <<< "$(echo -e "$repoUrls")"
  
  exit 0
}


# Processes an argument and checks if it is a git clone link or a project ID,
# in order to update either a single branch, or an entire project.
#
UpdateBranchesOfArgument() {
  argument="$1"

  if [ "$(IsProject "$argument")" = "true" ]; then
    echo $(UpdateBranchesOfProject "$argument") >&2
	
  elif [ "$(IsCloneLink "$argument")" = "true" ]; then
    echo $(UpdateBranchesOfRepository "$argument") >&2

  else
    echo "Argument '$argument' is neither a valid git clone link, nor a BitBucket project!" >&2
  fi
}


# Returns true if the argument is a git clone link.
#
IsCloneLink() {
  checkedArg="$1"
  greppedArg=$(echo "$checkedArg" | grep -cx "https:.*\.git")
  
  if [ "$greppedArg" = "1" ]; then
    projectId=$(GetProjectIdFromCloneLink "$checkedArg")
    slug=$(GetRepositorySlugFromCloneLink "$checkedArg")
    echo $(IsUrlReachable "https://code.gerdi-project.de/rest/api/latest/projects/$projectId/repos/$slug" "$atlassianUserName" "$atlassianPassword")
  else
    echo false
  fi
}


# Returns true if the argument is a project.
#
IsProject() {
  checkedArg="$1"
  greppedArg=$(echo "$checkedArg" | grep -cxP "[A-Za-z]+")
  
  if [ "$greppedArg" = "1" ]; then
    echo $(IsUrlReachable "https://code.gerdi-project.de/rest/api/latest/projects/$checkedArg/" "$atlassianUserName" "$atlassianPassword")
  else
    echo false
  fi
}



###########################
#  BEGINNING OF EXECUTION #
###########################

# check early exit conditions
ExitIfNotLoggedIn
ExitIfPlanVariableIsMissing "atlassianPassword"
ExitIfPlanVariableIsMissing "projectsAndCloneLinks"
ExitIfPlanVariableIsMissing "createdBranchName"
ExitIfPlanVariableIsMissing "sourceBranchName"

atlassianUserName=$(GetBambooUserName)
atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

# test Atlassian credentials
ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"
  
# get more Atlassian user details
atlassianUserEmail=$(GetAtlassianUserEmailAddress "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")

# get plan variables
createdBranchName=$(GetValueOfPlanVariable createdBranchName)
sourceBranchName=$(GetValueOfPlanVariable sourceBranchName)
projectsAndCloneLinks=$(GetValueOfPlanVariable "projectsAndCloneLinks" | tr -d " " | tr "," "\n")

# iterate through all clone links and/or projects
while read projectOrCloneLink
do 
  $(UpdateBranchesOfArgument $projectOrCloneLink)
done <<< "$(echo -e "$projectsAndCloneLinks")"


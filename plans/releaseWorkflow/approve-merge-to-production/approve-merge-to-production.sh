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
 
# This script approves and merges all Pull-requests for the current release.
# It then iterates through the list of released projects and/or git clone links and adds
# release version tags, if nothing has changed in the production branch since the previous release.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#
# Expected Bamboo Global Variables:
#  RELEASED_REPOSITORIES a list of repositories and Bitbucket projects that are to be released
#  PRODUCTION_VERSION the production version to be released


# treat unset variables as an error when substituting
set -u

source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/misc-utils.sh
source ./scripts/helper-scripts/git-utils.sh

#########################
#  FUNCTION DEFINITIONS #
#########################


# Iterates a list of untagged repositories and adds release version tags to the production branches.
#
# Arguments
#  1 - an Atlassian user that can tag all repositories
#  2 - the password for the Atlassian user
#  3 - a list of git clone links of which the production branches should be tagged
#
AddMissingReleaseTags() {
  local userName="$1"
  local password="$2"
  local unchangedRepositories="$3"

  local missingTagMessage="Nothing was added in release $bamboo_PRODUCTION_VERSION!"
  local repositoryArguments="'$userName' '$password' '$bamboo_PRODUCTION_VERSION' '$missingTagMessage'"
  
  ProcessListOfProjectsAndRepositories \
    "$userName" \
    "$password" \
    "$unchangedRepositories" \
    "AddTagToRepositoryIfMissing" \
    "$repositoryArguments"
}


# Adds a specified tag to the production branch of a specified repository, if
# it is missing.
#
# Arguments:
#  1 - the git clone link of the repository
#  2 - the Atlassian user that adds the tag
#  3 - the password for the Atlassian user
#  4 - The name of the tag to be added
#  5 - The message that is added to the tag
#
AddTagToRepositoryIfMissing() {
  local cloneLink="$1"
  local userName="$2"
  local password="$3"
  local tagName="$4"
  local tagMessage="$5"
  
  local projectId
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")
  
  local slug
  slug=$(GetRepositorySlugFromCloneLink "$cloneLink")
  
  if ! $(HasBitbucketTag "$userName" "$password" "$projectId" "$slug" "$tagName"); then
    AddBitbucketTag "$userName" "$password" "$projectId" "$slug" "production" "$tagName" "$tagMessage"
  fi
}


# Retrieves a list of git clone links of repositories that do not have an open 
# pull-request with the specified user as a reviewer.
#
# Arguments:
#  1 - an Atlassian user that is the reviewer of the pull-requests
#  2 - the password for the Atlassian user
#  3 - the title of the pull-requests
#
GetUnchangedRepositories() {
  local userName="$1"
  local password="$2"
  local title="$3"
  
  local reposWithPullRequests  
  reposWithPullRequests=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/dashboard/pull-requests?state=open&role=REVIEWER" \
    | perl -pe 's~.*?{"id":\d+,"version":\d+?,"title":"[^"]*?'"$title"'[^"]*?",.*?"toRef":.*?"href":"ssh:[^"]+?/([^/]+?)/([^/]+?)\.git"~'"\1 \2\n"'~gi' \
    | head -n -1)
  
  echo "$reposWithPullRequests"
  
  # create temporary file to store the list of repositories
  rm -f tempFile.txt
  touch tempFile.txt
  ProcessListOfProjectsAndRepositories \
    "$userName" \
    "$password" \
    "$bamboo_RELEASED_REPOSITORIES" \
    "AddToUnchangedRepositories" \
    "'$reposWithPullRequests'"
    
  cat tempFile.txt
}


# Checks if a git clone link is in a list of repositories that have open pull-requests.
#
# Arguments:
#  1 - the git clone link that is to be checked
#  2 - a list of space-separated projectId/repositorySlug pairs of repositories that have pull-requests
#
AddToUnchangedRepositories() {
  local cloneLink="$1"
  local reposWithPullRequests="$2"
  
  local projectId
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")
  
  local slug
  slug=$(GetRepositorySlugFromCloneLink "$cloneLink") 
  
  # write to temporary file if it is not in the list of pull requests and not inside the temporary file yet
  if ! $(echo "$reposWithPullRequests" | grep -q "$projectId $slug") \
     && [ -f tempFile.txt ] \
     && ! $(grep -q "$cloneLink" "tempFile.txt"); then
       echo "$cloneLink" >> tempFile.txt
  fi
}


# The main function that is called by this script.
Main() {
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "RELEASED_REPOSITORIES"

  local atlassianUserName=$(GetBambooUserName)
  local atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")
  
  local title="Merge to Production $bamboo_PRODUCTION_VERSION"
  local unchangedRepositories=$(GetUnchangedRepositories "$atlassianUserName" "$atlassianPassword" "$title")

  # approve all pull-requests
  ApproveAllPullRequestsWithTitle "$atlassianUserName" "$atlassianPassword" "$title"
  
  # merge all pull-requests
  MergeAllPullRequestsWithTitle "$atlassianUserName" "$atlassianPassword" "$title"
  
  # add missing tags
  echo "Adding missing release tags..." >&2
  AddMissingReleaseTags "$atlassianUserName" "$atlassianPassword" "$unchangedRepositories"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
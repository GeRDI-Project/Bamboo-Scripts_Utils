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

# This script is called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-CHPL which creates/overwrites
# Bamboo jobs for an existing harvester project.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  gitCloneLink - the clone link of a git repository
#  overwriteExistingJobs - if true, overwrites jobs if they already exist for the harvester


# treat unset variables as an error when substituting
set -u

# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


# Checks if a remote branch of a non-checked-out BitBucket repository exists and
# creates one out of the latest master branch commit, if it does not exist.
#  Arguments:
#   1 - Bitbucket user name
#   2 - Bitbucket user password
#   3 - Bitbucket Project ID
#   4 - Repository slug
#   5 - The name of the branch that is to be checked
#
CreateBitbucketBranch() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local branchName="$5"
  
  local response
  response=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/branches/?filterText=$branchName")
  
  # make sure that no branch with the same name exists
  if ! $(echo "$response" | grep -q "\"id\":\"refs/heads/$branchName\""); then
    local revision
	revision=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/branches/?filterText=master"\
	          | grep -oP "(?<=\"id\":\"refs/heads/master\",\"displayId\":\"master\",\"type\":\"BRANCH\",\"latestCommit\":\")[^\"]+")
			  
    echo "Creating Bitbucket branch '$branchName' for repository '$project/$repositorySlug', revision '$revision'." >&2
	
    response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
      "name": "'"$branchName"'",
      "startPoint": "'"$revision"'",
      "message": "Bamboo automatically created this branch in order to support Continuous Deployment."
    }' "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/branches/")
  fi
}


# Updates a Bitbucket repository, adding missing branches and user permissions.
#
UpdateRepository() {
  local username="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"

  # grant the bamboo-agent the permission to tag the repository
  AddWritePermissionForRepository "$username" "$password" "$project" "$repositorySlug" "bamboo-agent"

  # create branch model
  CreateBitbucketBranch "$username" "$password" "$project"  "$repositorySlug" "stage"
  CreateBitbucketBranch "$username" "$password" "$project"  "$repositorySlug" "production"
}


# Retrieves the provider name without spaces and special characters.
#
GetProviderClassName() {
  local username="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  
  local proviCLassName
  proviClassName=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/files" \
  | grep -oP "(?<=src/main/java/de/gerdiproject/harvest/)[^\"]+(?=ContextListener.java\")")
  
  if [ -z "$proviClassName" ]; then
    proviClassName=$(curl -sX GET "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/files" \
    | grep -oP "(?<=src/main/java/de/gerdiproject/harvest/)[^\"]+(?=ContextListener.java\")")
  fi
  
  echo "$proviClassName"
}


# The main function of this script.
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "gitCloneLink"

  local atlassianUserName
  atlassianUserName=$(GetBambooUserName)
  
  local atlassianPassword
  atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

  # retrieve plan variables
  local gitCloneLink
  gitCloneLink=$(GetValueOfPlanVariable gitCloneLink)
  
  local project
  project=$(GetProjectIdFromCloneLink "$gitCloneLink")

  local repositorySlug
  repositorySlug=$(GetRepositorySlugFromCloneLink "$gitCloneLink")
  
  echo "Repository: https://code.gerdi-project.de/projects/$project/repos/$repositorySlug/" >&2
  
  local providerClassName
  providerClassName=$(GetProviderClassName "$atlassianUserName" "$atlassianPassword" "$project" "$repositorySlug")
  
  if [ -z "$providerClassName" ]; then
    echo "Could not find ContextListener java class of repository '$project/$repositorySlug'!" >&2
	exit 1
  fi
  
  echo "Provider Class Name: '$providerClassName'" >&2
  
  # check if a plan with the same ID already exists in CodeAnalysis
  local planKey
  planKey="$(echo "$providerClassName" | sed -e "s~[a-z]~~g")HAR"
  
  # check if plans already exist
  if $(IsUrlReachable "https://ci.gerdi-project.de/rest/api/latest/plan/CA-$planKey" "$atlassianUserName" "$atlassianPassword"); then
    echo "Plans with the key '$planKey' already exist!" >&2
    exit 1
  fi
  
  # update repository
  UpdateRepository "$atlassianUserName" "$atlassianPassword" "$project" "$repositorySlug"

  # run Bamboo Specs
  ./scripts/plans/util/create-jobs-for-harvester/setup-bamboo-jobs.sh "$atlassianUserName" "$atlassianPassword" "$providerClassName" "$project" "$repositorySlug"
}

Main "$@"
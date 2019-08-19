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
source ./scripts/helper-scripts/bitbucket-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


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
  local project="$1"
  local repositorySlug="$2"
  
  local allFiles
  allFiles=$(GetJoinedAtlassianResponse \
           "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/files")
		   
  echo "$allFiles" \
        | grep -oP "(?<=src/main/java/de/gerdiproject/harvest/)[^\"]+(?=ContextListener.java\")"
}


# Creates jobs for a specified repository.
#
ProcessRepository() {
  local gitCloneLink="$1"
  local atlassianUserName="$2"
  local atlassianPassword="$3"
  local overwriteExistingJobs="$4"
  
  local project
  project=$(GetProjectIdFromCloneLink "$gitCloneLink")

  local repositorySlug
  repositorySlug=$(GetRepositorySlugFromCloneLink "$gitCloneLink")
  
  echo "Repository: https://code.gerdi-project.de/projects/$project/repos/$repositorySlug/" >&2
  
  ProcessHarvesterRepository  "$project" "$repositorySlug" "$atlassianUserName" "$atlassianPassword" "$overwriteExistingJobs"
}


ProcessHarvesterRepository() {
  local project="$1"
  local repositorySlug="$2"
  local atlassianUserName="$3"
  local atlassianPassword="$4"
  local overwriteExistingJobs="$5"
  
  local providerClassName
  providerClassName=$(GetProviderClassName "$project" "$repositorySlug")
  
  if [ -z "$providerClassName" ]; then
    echo "Repository'$project/$repositorySlug' is not a harvester!" >&2
	exit 1
  fi
  
  echo "Harvester Provider Class Name: '$providerClassName'" >&2
  
  # check if a plan with the same ID already exists in CodeAnalysis
  local planKey
  planKey="$(echo "$providerClassName" | sed -e "s~[a-z]~~g")HAR"
  
  # check if plans already exist
  if ! $overwriteExistingJobs && $(IsUrlReachable "https://ci.gerdi-project.de/rest/api/latest/plan/CA-$planKey" "$atlassianUserName" "$atlassianPassword"); then
    echo "Plans with the key '$planKey' already exist!" >&2
    exit 1
  fi
  
  # update repository
  UpdateRepository "$atlassianUserName" "$atlassianPassword" "$project" "$repositorySlug"

  # run Bamboo Specs
  ./scripts/plans/util/create-jobs-for-harvester/setup-bamboo-jobs.sh "$atlassianUserName" "$atlassianPassword" "$providerClassName" "$project" "$repositorySlug"
}


# The main function of this script.
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "projectsAndCloneLinks"
  ExitIfPlanVariableIsMissing "overwriteExistingJobs"
  ExitIfBambooVariableNotBoolean "overwriteExistingJobs"

  local atlassianUserName
  atlassianUserName=$(GetBambooUserName)
  
  local atlassianPassword
  atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"
  
  # retrieve other plan variables
  local projectsAndCloneLinks
  projectsAndCloneLinks=$(GetValueOfPlanVariable projectsAndCloneLinks)
  
  local overwriteExistingJobs
  overwriteExistingJobs=$(GetValueOfPlanVariable overwriteExistingJobs)
  
  local repoArguments="'$atlassianUserName' '$atlassianPassword' '$overwriteExistingJobs'"
  ProcessListOfProjectsAndRepositories \
    "$atlassianUserName" \
    "$atlassianPassword" \
    "$projectsAndCloneLinks" \
    "ProcessRepository" \
    "$repoArguments"
}

Main "$@"
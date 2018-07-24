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
 
# This script approves and merges all Pull-requests from the master to the stage branch for the upcoming release.
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

#########################
#  FUNCTION DEFINITIONS #
#########################


# The main function that is called by this script.
Main() {
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "RELEASED_REPOSITORIES"

  local atlassianUserName=$(GetBambooUserName)
  local atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")
  
  local title = "Merge to Staging $bamboo_STAGING_VERSION"

  # approve all pull-requests
  ApproveAllPullRequestsWithTitle "$atlassianUserName" "$atlassianPassword" "$title"
  
  # merge all pull-requests
  MergeAllPullRequestsWithTitle "$atlassianUserName" "$atlassianPassword" "$title"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
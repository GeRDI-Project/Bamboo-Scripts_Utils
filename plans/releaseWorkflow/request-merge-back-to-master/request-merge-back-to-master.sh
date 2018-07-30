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
 
# This script is called by a Bamboo Job. It creates pull-requests for
# merging back all production to master branches.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  reviewer - the reviewer for the pull request

# treat unset variables as an error when substituting
set -u
  
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################


# Main function that is executed by this script
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "RELEASED_REPOSITORIES"
  ExitIfPlanVariableIsMissing "PRODUCTION_VERSION"
  ExitIfPlanVariableIsMissing "reviewer"

  local atlassianUserName=$(GetBambooUserName)
  local atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"
  
  local title
  title="Merge Release $bamboo_PRODUCTION_VERSION back to Master"
  
  local description
  description="All production branches are to be merged to master to apply changes that came in during feature freeze of a release, or during a hotfix."
  
  local reviewer
  reviewer=$(GetValueOfPlanVariable reviewer)
  
  ./scripts/plans/releaseWorkflow/merge-branches.sh \
   "$atlassianUserName" \
   "$atlassianPassword" \
   "production" \
   "master" \
   "$bamboo_RELEASED_REPOSITORIES" \
   "$title" \
   "$description" \
   "$reviewer"
}

###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"


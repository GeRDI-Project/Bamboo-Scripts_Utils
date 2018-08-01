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
 
# This script is called by a Bamboo Job. It sets the version of the global Bamboo variable
# PRODUCTION_VERSION to that of the variable STAGING_VERSION and merges all stage to production branches.
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


# Changes the global bamboo variable 'PRODUCTION_VERSION' to the
# 'STAGING_VERSION' and returns the new value.
#
# Arguments:
#  1 - the Atlassian user name of an administrator
#  2 - the corresponding Atlassian password
#
ChangeGlobalReleaseVariable() {
  local userName="$1"
  local password="$2"
  
  local stagingVersion="$bamboo_STAGING_VERSION"

  if [ -z "$stagingVersion" ]; then
    stagingVersion="0.0.0"
  fi

  if $(SetGlobalVariable "PRODUCTION_VERSION" "$stagingVersion" "$userName" "$password"); then
    echo "Set PRODUCTION_VERSION to $stagingVersion!" >&2
  fi
  
  echo "$stagingVersion"  
}

# Main function that is executed by this script
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "RELEASED_REPOSITORIES"
  ExitIfPlanVariableIsMissing "reviewer"

  local atlassianUserName=$(GetBambooUserName)
  local atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"
  
  nextReleaseVersion=$(ChangeGlobalReleaseVariable "$atlassianUserName" "$atlassianPassword")
  
  local title
  title="Merge to Production $nextReleaseVersion"
  
  local description
  description="All staging branches are to be merged to production for the Release $nextReleaseVersion."
  
  local reviewer
  reviewer=$(GetValueOfPlanVariable reviewer)
  
  ./scripts/plans/releaseWorkflow/merge-branches.sh \
   "$atlassianUserName" \
   "$atlassianPassword" \
   "stage" \
   "production" \
   "$bamboo_RELEASED_REPOSITORIES" \
   "$title" \
   "$description" \
   "$reviewer"
}

###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"


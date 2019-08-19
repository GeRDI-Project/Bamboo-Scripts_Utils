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
 
# This script is called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-MHVU
# It attempts to find the last successful build of the plan https://ci.gerdi-project.de/browse/UTIL-UHV that creates a JIRA ticket
# with associated branches and pull requests for updating Maven Parent versions of Harvester projects.
# This script attempts to merge all approved pull requests of said JIRA ticket and removes the feature branches afterwards.
# If all branches were merged, the JIRA ticket is set to DONE.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  jiraIssueKey - (optional) the key of the JIRA ticket that is to be merged. If left blank, the ticket key 
#                 will be retrieved from the last https://ci.gerdi-project.de/browse/UTIL-UHV build 

# treat unset variables as an error when substituting
set -u

# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/bitbucket-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################


# Attempts to merge all open pull-requests of a JIRA-issue and sets the
# issue to "Done" if successful.
#
# Arguments:
#  1 - the issue key of a JIRA ticket to be merged and set to Done
#  2 - an Atlassian user name
#  3 - the password for the Atlassian user name
#
FinishAndMergeJiraTicket() {
  local jiraKey="$1"
  local atlassianUserName="$2"
  local atlassianPassword="$3"
  
  # merge all pull-requests
  local failedMerges
  failedMerges=$(MergeAllPullRequestsOfJiraTicket "$atlassianUserName" "$atlassianPassword" "$jiraKey")

  # set ticket to done
  if [ "$failedMerges" = "0" ]; then
    ReviewJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
    FinishJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  else
    echo "Cannot merge $failedMerges branches of JIRA issue $jiraKey" >&2
  fi
  
  # increment total merge fail count
  TOTAL_MERGE_FAILS=$(expr $TOTAL_MERGE_FAILS + $failedMerges)
}


# Attempts to retrieve a JIRA issue key from the plan variable "jiraIssueKey".
# If the plan variable is left empty, the issue key is retrieved from the last successful build
# of the "Update Harvester Versions" Bamboo job (UH-UHV).
#
# Arguments:
#  1 - an Atlassian user name
#  2 - the password for the Atlassian user name
#
GetJiraKey() {
  local atlassianUserName="$1"
  local atlassianPassword="$2"

  local jiraKey
  jiraKey=$(GetValueOfPlanVariable "jiraIssueKey")
    
  if [ -z "$jiraKey" ]; then
    echo "No JIRA issue key was specified. Trying to retrieve it from the last build of https://ci.gerdi-project.de/browse/UH-UHV master." >&2
	
	local latestPlanId
    latestPlanId=$(GetLatestBambooPlanResultKey "UH-UHV" "" "$atlassianUserName" "$atlassianPassword")
	
	local latestPlanLog
    latestPlanLog=$(curl -nsX GET "https://ci.gerdi-project.de/download/UH-UHV-JOB1/build_logs/UH-UHV-JOB1-$latestPlanId.log")
	
    jiraKey=$(echo "$latestPlanLog" | grep -oP '(?<=Created JIRA task )\w+?-\d+')
    
    if [ -n "$jiraKey" ]; then
      echo "Retrieved JIRA issue key: $jiraKey" >&2
    fi
  fi
  
  echo "$jiraKey"
}


# The main function to be called by this script.
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"

  # get and verify credentials
  local atlassianUserName
  atlassianUserName=$(GetBambooUserName)
  
  local atlassianPassword
  atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")
  
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

  # check if a JIRA key was specified
  local jiraKey
  jiraKey=$(GetJiraKey "$atlassianUserName" "$atlassianPassword" )
  if [ -z "$jiraKey" ]; then
    echo "Could not retrieve JIRA issue key!" >&2
    exit 1
  fi
  
  # define global variables
  TOTAL_MERGE_FAILS=0

  # merge all pull-requests
  IterateSubtasksOfJiraTicket "$jiraKey" "FinishAndMergeJiraTicket" "'"$atlassianUserName"' '"$atlassianPassword"'" >&2
  
  echo " " >&2
  if [ $TOTAL_MERGE_FAILS -eq 0 ]; then
    FinishJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"

    echo "----------------------------------------" >&2
    echo "FINISHED MERGING ALL OPEN PULL_REQUESTS!" >&2
    echo "----------------------------------------" >&2
  else
    echo "-----------------------------------------------------------------" >&2
    echo "UNABLE TO MERGE $TOTAL_MERGE_FAILS PULL_REQUEST(S)! PLEASE, CHECK THE JIRA TICKET:" >&2
    echo "https://tasks.gerdi-project.de/browse/$jiraKey" >&2
    echo "-----------------------------------------------------------------" >&2
  fi
  echo " " >&2
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
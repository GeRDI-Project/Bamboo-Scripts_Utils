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
 
# This script is being called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-MHVU
# It attempts to find the last successful build of the plan https://ci.gerdi-project.de/browse/UTIL-UHV that creates a JIRA ticket
# with associated branches and pull requests for updating Maven Parent versions of Harvester projects.
# This script attempts to merge all approved pull requests of said JIRA ticket and removes the feature branches afterwards.
# If all branches were merged, the JIRA ticket is set to DONE.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  jiraIssueKey - the key of the JIRA ticket that is to be merged. If left blank, the ticket key 
#                 will be retrieved from the last https://ci.gerdi-project.de/browse/UTIL-UHV build 


# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/git-utils.sh

# check early exit conditions
ExitIfNotLoggedIn
ExitIfPlanVariableIsMissing "atlassianPassword"
ExitIfPlanVariableIsMissing "jiraIssueKey"

atlassianUserName=$(GetBambooUserName)
atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")
atlassianCredentials="$atlassianUserName:$atlassianPassword"

# test Atlassian credentials
ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

# check if a JIRA key was specified
jiraKey=$(GetValueOfPlanVariable "jiraIssueKey")
  
if [ "$jiraKey" = "" ]; then
  echo "No JIRA issue key was specified. Trying to retrieve it from the last build of https://ci.gerdi-project.de/browse/UTIL-UHV master." >&2
  latestPlanId=$(GetLatestBambooPlanResultKey "UTIL-UHV" "" "$atlassianUserName" "$atlassianPassword")
  latestPlanLog=$(curl -sX GET -u "$atlassianCredentials" https://ci.gerdi-project.de/download/UTIL-UHV-JOB1/build_logs/UTIL-UHV-JOB1-$latestPlanId.log)
  jiraKey=$(echo "$latestPlanLog" | grep -oP '(?<=Created JIRA task )\w+?-\d+')
  
  if [ "$jiraKey" != "" ]; then
    echo "Retrieved JIRA issue key: $jiraKey" >&2
  else
    echo "Could not retrieve JIRA issue key. Please, run the plan customized and specify the variable!" >&2
    exit 1
  fi
fi

# merge all pull-requests
failedMerges=$(MergeAllPullRequestsOfJiraTicket "$jiraKey" "$atlassianUserName" "$atlassianPassword")

echo " " >&2
if [ $failedMerges -eq 0 ]; then
  FinishJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"

  echo "----------------------------------------" >&2
  echo "FINISHED MERGING ALL OPEN PULL_REQUESTS!" >&2
  echo "----------------------------------------" >&2
else
  echo "-----------------------------------------------------------------" >&2
  echo "UNABLE TO MERGE $failedMerges PULL_REQUEST(S)! PLEASE, CHECK THE JIRA TICKET:" >&2
  echo "https://tasks.gerdi-project.de/browse/$jiraKey" >&2
  echo "-----------------------------------------------------------------" >&2
fi

echo " " >&2
#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
 
# This script is being called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-MHVU
# It attempts to find the last successful build of the plan https://ci.gerdi-project.de/browse/UTIL-UHV that creates a JIRA ticket
# with associated branches and pull requests for updating Maven Parent versions of Harvester projects.
# This script attempts to merge all approved pull requests of said JIRA ticket and removes the feature branches afterwards.
# If all branches were merged, the JIRA ticket is set to DONE.
#
# Bamboo Variables:
#  bamboo_ManualBuildTriggerReason_userName - the login name of the current user
#  bamboo_passwordGit - the Atlassian password of the current user
#  bamboo_jiraIssueKey - the key of the JIRA ticket that is to be merged. If left blank, the ticket key 
#                        will be retrieved from the last https://ci.gerdi-project.de/browse/UTIL-UHV build 


# FUNCTION FOR SETTING UP ATLASSIAN LOGIN CREDENTIALS
InitAtlassianUserDetails() {
  # check if user is logged in
  if [ "$bamboo_ManualBuildTriggerReason_userName" = "" ]; then
    echo "You need to be logged in to run this job!" >&2
    exit 1
  fi
  
  # get user name
  atlassianUserName="$bamboo_ManualBuildTriggerReason_userName"
  echo "UserName: $atlassianUserName" >&2
  
  # check if password is set
  if [ "$bamboo_atlassianPassword" = "" ]; then
    echo "You need to specify your Atlassian password by setting the 'atlassianPassword' plan variable when running the plan customized!" >&2
    exit 1
  fi
  
  # assemble username+password for Atlassian REST requests
  atlassianCredentials="$atlassianUserName:$bamboo_atlassianPassword"
  
  # assemble username+password for Git Clones
  gitCredentials="$(echo "$atlassianUserName" | sed -e "s/@/%40/g"):$bamboo_atlassianPassword"
  
  # check if password is valid
  response=$(curl -sI -X HEAD -u "$atlassianCredentials" https://code.gerdi-project.de/rest/api/latest/projects/)
  httpCode=$(echo "$response" | grep -oP '(?<=HTTP/\d\.\d )\d+')
  if [ "$httpCode" != "200" ]; then
    echo "The 'atlassianPassword' plan variable is incorrect for user '$atlassianUserName'." >&2
    exit 1
  fi
  
  # get user profile
  userProfile=$(curl -sX GET -u "$atlassianCredentials" https://tasks.gerdi-project.de/rest/api/2/user?username="$atlassianUserName")
  
  # retrieve email from user profile
  atlassianUserEmail=$(echo "$userProfile" | grep -oP "(?<=\"emailAddress\":\")[^\"]+")
  echo "UserEmail: $atlassianUserEmail" >&2
  
  # retrieve displayName from user profile
  atlassianUserDisplayName=$(echo "$userProfile" | grep -oP "(?<=\"displayName\":\")[^\"]+")
  echo "UserDisplayName: $atlassianUserDisplayName" >&2
}


# FUNCTION FOR SETTING UP GLOBAL VARIABLES
InitVariables() {
  InitAtlassianUserDetails

  # check pull-request reviewers
  jiraKey="$bamboo_jiraIssueKey"
  if [ "$jiraKey" = "" ]; then
    echo "No JIRA issue key was specified. Trying to retrieve it from the last build of https://ci.gerdi-project.de/browse/UTIL-UHV master." >&2
    jiraKey=$(RetrieveJiraKeyFromPlan)
	
	if [ "$jiraKey" != "" ]; then
	  echo "Retrieved JIRA issue key: $jiraKey" >&2
	else
	  echo "Could not retrieve JIRA issue key. Please, run the plan customized and specify the variable!" >&2
	  exit 1
	fi
  fi
  
  topDir=$(pwd)
}


# FUNCTION THAT RETRIEVES THE JIRA KEY OF THE LATEST 'Update Harvester Versions' BUILD
RetrieveJiraKeyFromPlan() {
  planLabel="UTIL-UHV"
  latestPlanId=$(GetLatestBambooPlan "$planLabel" "")
  
  latestPlanLog=$(curl -sX GET -u "$atlassianCredentials" https://ci.gerdi-project.de/download/$planLabel-JOB1/build_logs/$planLabel-JOB1-$latestPlanId.log)
  latestJiraKey=$(echo "$latestPlanLog" | grep -oP '(?<=Created JIRA task )\w+?-\d+')
  
  echo "$latestJiraKey"
}


# FUNCTION FOR SETTING A JIRA ISSUE TO DONE
FinishJiraTask() {
  taskKey="$1"
  
  echo "Setting $taskKey to 'Done'" >&2
  jiraPostResponse=$(curl -sX POST -u "$atlassianCredentials" -H "Content-Type: application/json" -d '{
    "transition": {"id": 71}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR MERGING ALL PULL REQUEST OF A JIRA TICKET
MergeAllPullRequestsOfJiraIssue() {
  jiraKey="$1"
  
  allCommits="$(curl -sX GET -u "$atlassianCredentials" https://code.gerdi-project.de/rest/jira/latest/issues/$jiraKey/commits?maxChanges\=1)"
  
  # filter out all Merge commits
  allCommits=$(printf "%s" "$allCommits" | grep -oP '{"fromCommit".*?"message":"'"$jiraKey"'.*?}}}')
  
  # create set of instruction parameters: jiraKey, branchName, project, slug
  instructionParamList=$(printf "%s" "$allCommits" | sed -e 's~.*"message":"'"$jiraKey"' \(.\+\?\) Updated.*"href":"http[^"]\+\?/\([^"]\+\?\)/\([^"]\+\?\).git".*~'"$jiraKey"' '"$jiraKey"'-\1-VersionUpdate \2 \3~g')
  
  # execute merge of all pull-requests
  failedMerges=0
  printf '%s\n' "$instructionParamList" | ( while IFS= read -r params
  do 
    isMerged=$(ProcessPullRequest $params)
	failedMerges=$(expr $failedMerges + $isMerged)
  done
  echo $failedMerges )
}


# MERGES A SINGLE PULL REQUEST AND CLEANS UP THE BRANCH
ProcessPullRequest() {
  jiraKey="$1"
  branchName="$2"
  project="$3"
  slug="$4"
  
  pullRequestId=$(GetPullRequestIdForJiraIssue "$slug" "$project" "$jiraKey")
  
  if [ "$pullRequestId" != "" ]; then
    pullRequestInfo=$(curl -sX GET -u "$atlassianCredentials" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$slug/pull-requests/$pullRequestId)
    pullRequestStatus=$(GetPullRequestStatus "$pullRequestInfo")
  else
    pullRequestStatus="MERGED"
  fi
  
  if [ "$pullRequestStatus" = "MERGED" ]; then
    echo "No need to merge https://code.gerdi-project.de/projects/$project/repos/$slug/ because it was already merged!" >&2
    DeleteBranch "$slug" "$project" "$branchName"
	wasMerged=0
	
  elif [ "$pullRequestStatus" = "APPROVED" ]; then
    echo "Merging https://code.gerdi-project.de/projects/$project/repos/$slug/pull-requests/$pullRequestId/" >&2
	  
    pullRequestVersion=$(GetPullRequestVersion "$pullRequestInfo")
    MergePullRequest "$slug" "$project" "$pullRequestId" "$pullRequestVersion" >&2
    DeleteBranch "$slug" "$project" "$branchName"
	wasMerged=0
	
  elif [ "$pullRequestStatus" = "NEEDS_WORK" ]; then
    echo "Could not merge https://code.gerdi-project.de/projects/$project/repos/$slug/pull-requests/$pullRequestId/ because it was not approved yet!" >&2
    wasMerged=1
  fi  
  
  echo $wasMerged
}


# FUNCTION THAT MERGES A PULL-REQUEST
MergePullRequest() {
  slug="$1"
  project="$2"
  pullRequestId="$3"
  pullRequestVersion="$4"
  
  mergeResponse=$(curl -sX POST -u "$atlassianCredentials" -H "Content-Type:application/json" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$slug/pull-requests/$pullRequestId/merge?version=$pullRequestVersion) >&2
}


# FUNCTION FOR REMOVING A REMOTE BRANCH
DeleteBranch() {
  slug="$1"
  project="$2"
  branchName="$3"
  
  branchInfo=$(curl -sX GET -u "$atlassianCredentials" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$slug/branches?filterText=$branchName)
  wasBranchDeleted=$(echo "$branchInfo" | grep -o '{"size":0,')
  
  if [ "$wasBranchDeleted" = "" ]; then
    echo "Deleting branch '$branchName' of '$project/$slug'" >&2
    deleteResponse=$(curl -sX DELETE -u "$atlassianCredentials" -H "Content-Type: application/json" -d '{
      "name": "refs/heads/'"$branchName"'",
      "dryRun": false
    }' https://code.gerdi-project.de/rest/branch-utils/latest/projects/$project/repos/$slug/branches/)
    echo "$deleteResponse" >&2
  else
    echo "No need to delete branch '$branchName' of '$project/$slug', because it no longer exists." >&2
  fi
}


# FUNCTION THAT RETURNS THE PULL-REQUEST ID OF A SPECIFIED REPOSITORY THAT IS LINKED TO A SPECIFIED JIRA ISSUE
GetPullRequestIdForJiraIssue() {
  slug="$1"
  project="$2"
  jiraKey="$3"
  allPullRequests=$(curl -sX GET -u "$atlassianCredentials" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$slug/pull-requests)
  
  hasNoOpenRequests=$(echo "$allPullRequests" | grep -o '{"size":0,')
  
  if [ "$hasNoOpenRequests" != "" ]; then
    pullRequestId=""
  else
    pullRequestId=${allPullRequests%\"fromRef\":\{\"id\":\"refs/heads/$jiraKey*}
    pullRequestId=${pullRequestId##*\"id\":}
    pullRequestId=${pullRequestId%%,*}
  fi
  
  echo "$pullRequestId"
}


# FUNCTION THAT RETURNS THE LATEST VERSION OF A PULL-REQUEST
GetPullRequestVersion() {
  pullRequestInfo="$1"
  echo "$pullRequestInfo" | grep -oP '(?<="version":)\d+'
}


# FUNCTION THAT RETURNS THE SOURCE BRANCH OF A PULL-REQUEST
GetPullRequestSourceBranch() {
  pullRequestInfo="$1"
  
  echo "$pullRequestInfo" | grep -oP '(?<="fromRef":{"id":").+?(?=")'
}

# FUNCTION THAT RETURNS A STATUS STRING OF A PULL-REQUEST
GetPullRequestStatus() {
  pullRequestInfo="$1"
  
  reviewerInfo=${pullRequestInfo#*\"reviewers\":\[}
  reviewerInfo=${reviewerInfo%%\],\"participants\":\[}
  
  # is the request already merged ? 
  mergedStatus=$(echo "$pullRequestInfo" | grep -o '"state":"MERGED","open":false,')
  
  # did any reviewer set the status to 'NEEDS_WORK' ?
  needsWorkStatus=$(echo "$reviewerInfo" | grep -o '"status":"NEEDS_WORK"')

  # at least one reviewer set the status to 'APPROVED'  
  approvedStatus=$(echo "$reviewerInfo" | grep -o '"status":"APPROVED"')
  
  if [ "$mergedStatus" != "" ]; then
    echo "MERGED"
  elif [ "$needsWorkStatus" = "" ] && [ "$approvedStatus" != "" ]; then
    echo "APPROVED"
  else
    echo "NEEDS_WORK"
  fi
}


# FUNCTION THAT RETURNS THE PLAN_RESULT_KEY OF THE LATEST BUILD OF A BAMBOO PLAN
GetLatestBambooPlan() {
  planLabel="$1"
  planBranchId="$2"
  
  # check latest finished build
  bambooGetResponse=$(curl -sX GET -u "$atlassianCredentials" -H "Content-Type: application/json"  https://ci.gerdi-project.de/rest/api/latest/result/$planLabel$planBranchId?max\-results=1)
  planResultKey=$(echo "$bambooGetResponse" | grep -oP '(?<=<buildResultKey>).+(?=</buildResultKey>)')
  
  # check if a build is in progress
  if [ "$planResultKey" != "" ]; then
    nextBuildNumber=${planResultKey##*-}
	nextBuildNumber=$(expr $nextBuildNumber + 1)
    nextPlanResultKey="${planResultKey%-*}-$nextBuildNumber"
    httpCode=$(GetHeadHttpCode "https://ci.gerdi-project.de/rest/api/latest/result/status/$nextPlanResultKey" "0")
	
	if [ "$httpCode" = "200" ]; then
	  planResultKey="$nextPlanResultKey"
	fi
  fi
  
  echo "$planResultKey"
}


# FUNCTION FOR RETRIEVING HTTP RESPONSE CODE
GetHeadHttpCode() {
  url="$1"
  isUsingAuth="$2"
  
  if [ $isUsingAuth -eq 0 ]; then
    sonaTypeResponse=$(curl -sI -X HEAD -u "$atlassianCredentials" $url)
  else
    sonaTypeResponse=$(curl -sI -X HEAD $url)
  fi
  
  httpCode=$(echo "$sonaTypeResponse" | grep -oP '(?<=HTTP/\d\.\d )\d+')
  echo "$httpCode"
}


# set up some variables
InitVariables

# merge all pull-requests
failedMerges=$(MergeAllPullRequestsOfJiraIssue "$jiraKey")

echo " " >&2
if [ $failedMerges -eq 0 ]; then
  FinishJiraTask "$jiraKey"

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
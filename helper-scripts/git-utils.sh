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


GetRepositorySlugFromCloneLink() {
  cloneLink="$1"
  
  repositorySlug=${cloneLink##*/}
  repositorySlug=${repositorySlug%.git}
  
  echo "$repositorySlug"
}


GetProjectIdFromCloneLink() {
  cloneLink="$1"
  
  projectId=${cloneLink%/*}
  projectId=${projectId##*/}
  
  echo "$projectId"
}


CloneGitRepository() {
  userName="$1"
  password="$2"
  projectId="$3"
  repositorySlug="$4"
  
  gitCredentials= "$(echo "$userName" | sed -e "s/@/%40/g"):$password"
  
  echo "Cloning repository code.gerdi-project.de/scm/$projectId/$repositorySlug.git" >&2
  response=$(git clone -q "https://$gitCredentials@code.gerdi-project.de/scm/$projectId/$repositorySlug.git")

  if [ $?  -ne 0 ]; then
    echo "Could not clone repository:" >&2
    echo "$response" >&2
    exit 1
  fi
}


CreateGitRepository() {
  userName="$1"
  password="$2"
  projectId="$3"
  repoName="$4"
  
  echo "Creating repository '$repoName' in code.gerdi-project.de/scm/$projectId/" >&2
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "name": "'"$repoName"'",
    "scmId": "git",
    "forkable": true
  }' https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/)

  # check for BitBucket errors
  errorsPrefix="\{\"errors\""
  if [ "${response%$errorsPrefix*}" = "" ]; then
    echo "Could not create repository for the Harvester:" >&2
    echo "$response" >&2
    exit 1
  fi

  # retrieve the urlencoded repository name from the curl response
  repositorySlug=${response#*\{\"slug\":\"}
  repositorySlug=${repositorySlug%%\"*}

  echo "Successfully created repository '$repositorySlug'." >&2
  
  echo "$repositorySlug"
}


DeleteGitRepository() {
  userName="$1"
  password="$2"
  projectId="$3"
  repositorySlug="$4"
 
  response=$(curl -sX DELETE -u "$userName:$password" https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug)
}


# FUNCTION FOR REMOVING A REMOTE BRANCH
DeleteBranch() {
  userName="$1"
  password="$2"
  project="$3"
  repositorySlug="$4"
  branchName="$5"
  
  branchInfo=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/branches?filterText=$branchName)
  wasBranchDeleted=$(echo "$branchInfo" | grep -o '{"size":0,')
  
  if [ "$wasBranchDeleted" = "" ]; then
    echo "Deleting branch '$branchName' of '$project/$repositorySlug'" >&2
    deleteResponse=$(curl -sX DELETE -u "$userName:$password" -H "Content-Type: application/json" -d '{
      "name": "refs/heads/'"$branchName"'",
      "dryRun": false
    }' https://code.gerdi-project.de/rest/branch-utils/latest/projects/$project/repos/$repositorySlug/branches/)
    echo "$deleteResponse" >&2
  else
    echo "No need to delete branch '$branchName' of '$project/$repositorySlug', because it no longer exists." >&2
  fi
}


PushAllFilesToGitRepository() {
  userDisplayName="$1"
  userEmailAddress="$2"
  commitMessage="$3"

  echo "Adding files to Git" >&2
  git add -A ${PWD}

  echo "Committing files to Git" >&2
  git config user.email "$userDisplayName"
  git config user.name "$userEmailAddress"
  git commit -m "$commitMessage"

  echo "Pushing files to Git" >&2
  git push -q
}


# FUNCTION FOR CREATING A PULL REQUEST
CreatePullRequest() {
  branch="$1"
  title="$2"
  description="$3"
  repositoryAddress="$4"
  userName="$5"
  password="$6"
  reviewer1="$7"
  reviewer2="$8"
  
  # retrieve repository slug
  repositorySlug=${repositoryAddress%.git}
  repositorySlug=${repositorySlug##*/}
  
  # retrieve project key
  projectKey=${repositoryAddress%/*}
  projectKey=${projectKey##*/}
  
  # print some debug log about the repository and reviewer(s)
  echo "Creating Pull-Request for repository '$repositorySlug' in project '$projectKey'." >&2
  
  if ["$reviewer1" != "" ] && ["$reviewer1" != "" ] ; then
    echo "Reviewers are $reviewer1 and $reviewer2." >&2
	
  elif ["$reviewer1" != "" ]; then
    echo "Reviewer is $reviewer1." >&2
	
  elif ["$reviewer2" != "" ]; then
    echo "Reviewer is $reviewer2." >&2
	
  else
    echo "No Reviewers are assigned." >&2
  fi
  
  # create pull-request
  bitbucketPostResponse=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "title": "'"$title"'",
    "description": "'"$description"'",
    "state": "OPEN",
    "open": true,
    "closed": false,
    "fromRef": {
        "id": "refs/heads/'"$branch"'",
        "repository": {
            "slug": "'"$repositorySlug"'",
            "name": null,
            "project": {
                "key": "'"$projectKey"'"
            }
        }
    },
    "toRef": {
        "id": "refs/heads/master",
        "repository": {
            "slug": "'"$repositorySlug"'",
            "name": null,
            "project": {
                "key": "'"$projectKey"'"
            }
        }
    },
    "locked": false,
    "reviewers": [
        { "user": { "name": "'"$reviewer1"'" }}
    ],
    "links": {
        "self": [
            null
        ]
    }
  }' https://code.gerdi-project.de/rest/api/latest/projects/$projectKey/repos/$repositorySlug/pull-requests)
}


# FUNCTION THAT RETURNS THE PULL-REQUEST ID OF A SPECIFIED REPOSITORY AND SOURCE BRANCH
GetPullRequestIdOfSourceBranch() {
  userName="$1"
  password="$2"
  project="$3"
  repositorySlug="$4"
  branchName="$5"
  allPullRequests=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/pull-requests)
  
  hasNoOpenRequests=$(echo "$allPullRequests" | grep -o '{"size":0,')
  
  if [ "$hasNoOpenRequests" != "" ]; then
    pullRequestId=""
  else
    pullRequestId=${allPullRequests%\"fromRef\":\{\"id\":\"refs/heads/$branchName}
    pullRequestId=${pullRequestId##*\"id\":}
    pullRequestId=${pullRequestId%%,*}
  fi
  
  echo "$pullRequestId"
}


# FUNCTION THAT MERGES A PULL-REQUEST
MergePullRequest() {
  userName="$1"
  password="$2"
  project="$3"
  repositorySlug="$4"
  pullRequestId="$5"
  pullRequestVersion="$6"
  
  mergeResponse=$(curl -sX POST -u "$userName:$password" -H "Content-Type:application/json" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId/merge?version=$pullRequestVersion) >&2
}


# MERGES A SINGLE PULL REQUEST AND REMOVES THE BRANCH
MergeAndCleanPullRequest() {
  userName="$1"
  password="$2"
  project="$3"
  repositorySlug="$4"
  branchName="$5"
  
  pullRequestId=$(GetPullRequestIdOfSourceBranch "$project" "$repositorySlug" "$branchName")
  if [ "$pullRequestId" != "" ]; then
    pullRequestInfoJson=$(GetPullRequestInfoJson "$userName" "$password" "$project" "$repositorySlug" "$pullRequestId")
    pullRequestStatus=$(GetStatusFromPullRequestInfoJson "$pullRequestInfoJson")
  else
    pullRequestStatus="MERGED"
  fi
  
  if [ "$pullRequestStatus" = "MERGED" ]; then
    echo "No need to merge https://code.gerdi-project.de/projects/$project/repos/$repositorySlug/ because it was already merged!" >&2
    DeleteBranch "$userName" "$password" "$project" "$repositorySlug" "$branchName"
	
  elif [ "$pullRequestStatus" = "APPROVED" ]; then
    echo "Merging https://code.gerdi-project.de/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId/" >&2
	  
    pullRequestVersion=$(GetVersionFromPullRequestInfoJson "$pullRequestInfoJson")
    MergePullRequest "$userName" "$password" "$project" "$repositorySlug" "$pullRequestId" "$pullRequestVersion" >&2
    DeleteBranch "$userName" "$password" "$project" "$repositorySlug" "$branchName"
	
  elif [ "$pullRequestStatus" = "NEEDS_WORK" ]; then
    echo "Could not merge https://code.gerdi-project.de/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId/ because it was not approved yet!" >&2
    exit 1
  fi  
}


# FUNCTION FOR MERGING ALL PULL REQUEST OF A JIRA TICKET
MergeAllPullRequestsOfJiraTicket() {
  userName="$1"
  password="$2"
  jiraKey="$3"
  
  # get all commits of JIRA ticket
  allCommits=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/jira/latest/issues/$jiraKey/commits?maxChanges\=1)
    
  # extract clone links from commits with messages that start with the JIRA ticket number
  cloneLinkList=$(printf "%s" "$allCommits" \
  | grep -oP '{"fromCommit".*?"message":"'"$jiraKey"'.*?}}}' \
  | sed -e 's~.*"message":"'"$jiraKey"'.*\?"href":"\(http[^"]\+\?git\)".*~\1~g')
  
  # execute merge of all pull-requests
  failedMerges=0
  printf '%s\n' "$cloneLinkList" | ( while IFS= read -r cloneLink
  do 
    project=$(GetProjectIdFromCloneLink "$cloneLink")
    repositorySlug=$(GetRepositorySlugFromCloneLink "$cloneLink")
	
	# get full branch name by looking for branches that start with the JIRA ticket number
    jiraBranchJson=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/branches?filterText=$jiraKey)
	branchName=$(echo $jiraBranchJson | grep -oP "(?<=\"id\":\"refs/heads/)[^\"]+")
	
    $(MergeAndCleanPullRequest "$userName" "$password" "$project" "$repositorySlug" "$branchName")
	isMerged=$?
	failedMerges=$(expr $failedMerges + $isMerged)
  done
  echo $failedMerges )
}


GetPullRequestInfoJson() {
  userName="$1"
  password="$2"
  project="$3"
  repositorySlug="$4"
  pullRequestId="$5"
  
  echo $(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId)
}


# FUNCTION THAT RETURNS THE LATEST VERSION OF A PULL-REQUEST
GetVersionFromPullRequestInfoJson() {
  pullRequestInfo="$1"
  echo "$pullRequestInfo" | grep -oP '(?<="version":)\d+'
}


# FUNCTION THAT RETURNS A STATUS STRING OF A PULL-REQUEST
GetStatusFromPullRequestInfoJson() {
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
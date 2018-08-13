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

# This script offers helper functions that concern Git and Atlassian Bitbucket of GeRDI.


# Returns the repository slug of a Git repository.
# The slug is a HTTP encoded identifier of a repository.
#  Arguments:
#  1 - a link to the repository (default: the first repository of the bamboo plan)
#
GetRepositorySlugFromCloneLink() {
  local cloneLink="${1-$bamboo_planRepository_1_repositoryUrl}"
  
  local repositorySlug
  repositorySlug=${cloneLink##*/}
  repositorySlug=${repositorySlug%.git}
  
  echo "$repositorySlug"
}


# Returns the project identifier of a Git repository.
#  Arguments:
#  1 - a link to the repository (default: the first repository of the bamboo plan)
#
GetProjectIdFromCloneLink() {
  local cloneLink="${1-$bamboo_planRepository_1_repositoryUrl}"
  
  local projectId
  projectId=${cloneLink%/*}
  projectId=${projectId##*/}
  
  echo "$projectId"
}


# Returns the number of unstaged files of the current git directory.
#  Arguments: -
#
GetNumberOfUnstagedChanges() {
  git diff --numstat | wc -l
}


# Clones a Git repository to the current directory.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#
CloneGitRepository() {
  local userName="$(echo "$1" | sed -e "s/@/%40/g")"
  local password="$2"
  local projectId="$3"
  local repositorySlug="$4"
  
  local gitCredentials
  gitCredentials="$userName:$password"
  
  echo "Cloning repository code.gerdi-project.de/scm/$projectId/$repositorySlug.git" >&2
  local response
  response=$(git clone -q "https://$gitCredentials@code.gerdi-project.de/scm/$projectId/$repositorySlug.git" .)

  if [ $?  -ne 0 ]; then
    echo "Could not clone repository:" >&2
    echo "$response" >&2
    exit 1
  fi
}


# Creates a new empty Git repository.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project in which the repository is created
#  4 - a human readable name of the repository
#
CreateGitRepository() {
  local userName="$1"
  local password="$2"
  local projectId="$3"
  local repoName="$4"
  
  echo "Creating repository '$repoName' in code.gerdi-project.de/scm/$projectId/" >&2
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "name": "'"$repoName"'",
    "scmId": "git",
    "forkable": true
  }' https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/)

  
  local repositorySlug
  repositorySlug=$(echo "$response" | grep -oP '(?<="slug":")[^"]+')
  
  # check if the slug was created
  if [ -z "$repositorySlug" ]; then 
    echo -e "Could not create repository for the Harvester:\n$response" >&2
    exit 1
  fi

  echo "Successfully created repository '$repositorySlug'." >&2
  echo "$repositorySlug"
}


# Deletes a Git repository.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository that is to be deleted
#
DeleteGitRepository() {
  local userName="$1"
  local password="$2"
  local projectId="$3"
  local repositorySlug="$4"
 
  local response
  response=$(curl -sX DELETE -u "$userName:$password" https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug)
}


# Retrieves the commit hash of the latest commit of a specified branch.
#
# Arguments:
#  1 - Bitbucket user name
#  2 - Bitbucket user password
#  3 - Bitbucket Project ID
#  4 - Repository slug
#  5 - The name of the branch of which the last commit is retrieved
GetLatestCommit() {
  local userName="$1"
  local password="$2"
  local projectId="$3"
  local repositorySlug="$4"
  local branch="$5"
  
  curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/branches/" \
     | grep -oP '(?<="displayId":"'"$branch"'","type":"BRANCH","latestCommit":")[^"]+'
}


# Retrieves a JSON object representing a tag in a Bitbucket repository.
#
# Arguments:
#  1 - Bitbucket user name
#  2 - Bitbucket user password
#  3 - Bitbucket Project ID
#  4 - Repository slug
#  5 - The name of the tag to be retrieved
#
GetBitbucketTag() {
  local userName="$1"
  local password="$2"
  local projectId="$3"
  local repositorySlug="$4"
  local tagName="$5"
  curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/tags/$tagName"
}


# Checks if a tag in a Bitbucket repository exists and exits with 1 if it does not.
#
# Arguments:
#  1 - Bitbucket user name
#  2 - Bitbucket user password
#  3 - Bitbucket Project ID
#  4 - Repository slug
#  5 - The name of the tag to be retrieved
#
HasBitbucketTag() {
  local userName="$1"
  local password="$2"
  local projectId="$3"
  local repositorySlug="$4"
  local tagName="$5"
  local response
  httpCode=$(curl -sIX HEAD -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/tags/$tagName" \
  | grep -oP '(?<=HTTP/\d\.\d )\d+')
  
  if [ "$httpCode" != "200" ]; then
    exit 1
  fi
}


# Tags a Bitbucket repository on a specified branch.
#
# Arguments:
#  1 - Bitbucket user name
#  2 - Bitbucket user password
#  3 - Bitbucket Project ID
#  4 - Repository slug
#  5 - The name of the branch that is to be tagged
#  6 - The name of the tag to be added
#  7 - The message that is added to the tag
#
AddBitbucketTag() {
  local userName="$1"
  local password="$2"
  local projectId="$3"
  local repositorySlug="$4"
  local branch="$5"
  local tagName="$6"
  local tagMessage="$7"
  
  local revision=$(GetLatestCommit "$userName" "$password" "$projectId" "$repositorySlug" "$branch")
  
  if [ -z "$revision" ]; then
    echo "Could not add tag '$tagName' to repository '$projectId/$repositorySlug'! Branch '$branch' does not exist." >&2
    exit 1
  fi
  
  local response=$(curl -sfX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "name": "'"$tagName"'",
    "startPoint": "'"$revision"'",
    "message": "'"$tagMessage"'"
  }' "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/tags")
  
  if [ $? -eq 0 ]; then
    echo "Added tag '$tagName' to repository '$projectId/$repositorySlug' on branch '$branch'." >&2
  else
    echo "Could not add tag '$tagName' to repository '$projectId/$repositorySlug' on branch '$branch'!" >&2
    exit 1
  fi
}


# Checks if a branch exists in a Bitbucket, without having to checkout the repository.
#
# Arguments:
#  1 - Bitbucket user name
#  2 - Bitbucket user password
#  3 - Bitbucket Project ID
#  4 - Repository slug
#  5 - The name of the branch that is to be checked
#
HasBitbucketBranch() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local branchName="$5"
  
  curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/branches/?filterText=$branchName" \
    | grep -q "\"id\":\"refs/heads/$branchName\""
}


# Creates a remote Git branch of the current repository.
#  Arguments:
#  1 - the name of the branch
#
CreateBranch() {
  local branchName="$1"
  echo $(git checkout -b $branchName) >&2
  echo $(git push -q --set-upstream origin $branchName) >&2
}


# Removes a branch from a Git repository.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the identifier of the branch that is to be deleted
#
DeleteBranch() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local branchName="$5"
  
  local branchInfo
  branchInfo=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/branches?filterText=$branchName)
  
  # only continue if the branch exists
  if ! $(echo "$branchInfo" | grep -q '"size":0'); then
    echo "Deleting branch '$branchName' of '$project/$repositorySlug'" >&2
	
	local deleteResponse
    deleteResponse=$(curl -sX DELETE -u "$userName:$password" -H "Content-Type: application/json" -d '{
      "name": "refs/heads/'"$branchName"'",
      "dryRun": false
    }' https://code.gerdi-project.de/rest/branch-utils/latest/projects/$project/repos/$repositorySlug/branches/)
	
    echo "$deleteResponse" >&2
  else
    echo "No need to delete branch '$branchName' of '$project/$repositorySlug', because it no longer exists." >&2
  fi
}

# Adds, commits, and pushes all files to Git.
#  Arguments:
#  1 - the full name of the user that pushes the files
#  2 - the email address of the user that pushes the files
#  3 - the commit message
#
PushAllFilesToGitRepository() {
  local userDisplayName="$1"
  local userEmailAddress="$2"
  local commitMessage="$3"

  echo "Adding files to Git" >&2
  git add -A

  echo "Committing files to Git" >&2
  git config user.email "$userDisplayName"
  git config user.name "$userEmailAddress"
  git commit -m "$commitMessage"

  echo "Pushing files to Git" >&2
  git push -q
}


# Creates a pull request to merge a branch to the master branch.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the identifier of the branch that is to be merged
#  6 - the identifier of the branch to which the merge is directed
#  7 - the title of the pull request
#  8 - the description of the pull request
#  9 - the Atlassian user name of a pull request reviewer (recommended)
#  10 - the Atlassian user name of another pull request reviewer (optional)
#
CreatePullRequest() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local branch="$5"
  local target="$6"
  local title="$7"
  local description="$8"
  local reviewer1="$9"
  local reviewer2="${10}"
  
  # print some debug log about the repository and reviewer(s)
  echo "Creating Pull-Request for repository '$repositorySlug' in project '$project'." >&2
  
  local reviewers="[]"
  if [ -n "$reviewer1" ] && [ -n "$reviewer2" ]; then
    echo "Reviewers are $reviewer1 and $reviewer2." >&2
    reviewers="[{ \"user\": { \"name\": \"$reviewer1\" }}, { \"user\": { \"name\": \"$reviewer2\" }}]"
	
  elif [ -n "$reviewer1" ]; then
    echo "Reviewer is $reviewer1." >&2
    reviewers="[{ \"user\": { \"name\": \"$reviewer1\" }}]"
	
  elif [ -n "$reviewer2" ]; then
    echo "Reviewer is $reviewer2." >&2
    reviewers="[{ \"user\": { \"name\": \"$reviewer2\" }}]"
	
  else
    echo "No Reviewers are assigned." >&2
  fi
  
  # create pull-request
  local bitbucketPostResponse
  curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
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
                "key": "'"$project"'"
            }
        }
    },
    "toRef": {
        "id": "refs/heads/'"$target"'",
        "repository": {
            "slug": "'"$repositorySlug"'",
            "name": null,
            "project": {
                "key": "'"$project"'"
            }
        }
    },
    "locked": false,
    "reviewers": '"$reviewers"',
    "links": {
        "self": [
            null
        ]
    }
  }' "https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/pull-requests"
}


# Returns the pull request identifier of a specified repository and source branch.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the identifier of the source branch
#
GetPullRequestIdOfSourceBranch() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local branchName="$5"
  
  local allPullRequests
  allPullRequests=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/pull-requests)
  
  local pullRequestId
  
  # check if there are no pull requests
  if $(echo "$allPullRequests" | grep -q '"{size":0,'); then
    pullRequestId=""
  else
    pullRequestId=${allPullRequests%\"fromRef\":\{\"id\":\"refs/heads/$branchName*}
    pullRequestId=${pullRequestId##*\"id\":}
    pullRequestId=${pullRequestId%%,*}
  fi
  
  echo "$pullRequestId"
}


# Merges a pull request.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the pull request
#  5 - the version of the pull request
#
MergePullRequest() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local pullRequestId="$5"
  local pullRequestVersion="$6"
  
  local mergeResponse
  mergeResponse=$(curl -sX POST -u "$userName:$password" -H "Content-Type:application/json" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId/merge?version=$pullRequestVersion) >&2
}


# Merges a pull request, if it exists, is approved and not merged.
# The corresponding feature branch is deleted if the merge was successful at any point.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the identifier of the source branch
#
MergeAndCleanPullRequest() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local branchName="$5"
  
  local pullRequestId
  pullRequestId=$(GetPullRequestIdOfSourceBranch "$userName" "$password" "$project" "$repositorySlug" "$branchName")
  
  local pullRequestInfoJson
  local pullRequestStatus
  if [ -n "$pullRequestId" ]; then
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
	
	local pullRequestVersion
    pullRequestVersion=$(GetVersionFromPullRequestInfoJson "$pullRequestInfoJson")
	
    MergePullRequest "$userName" "$password" "$project" "$repositorySlug" "$pullRequestId" "$pullRequestVersion" >&2
    DeleteBranch "$userName" "$password" "$project" "$repositorySlug" "$branchName"
	
  elif [ "$pullRequestStatus" = "NEEDS_WORK" ]; then
    echo "Could not merge https://code.gerdi-project.de/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId/ because it was not approved yet!" >&2
    exit 1
  fi  
}


# Checks all commits of a JIRA ticket and attempts to merge all corresponding branches
# that have open pull requests and a matching name.
# Returns the number of pull requests that could not be merged due to errors or non-approval.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the identifier of the JIRA ticket of which all pull requests are merged
#
MergeAllPullRequestsOfJiraTicket() {
  local userName="$1"
  local password="$2"
  local jiraKey="$3"
  
  # get all commits of JIRA ticket
  local allCommits
  allCommits=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/jira/latest/issues/$jiraKey/commits?maxChanges\=1)
  
  # extract clone links from commits with messages that start with the JIRA ticket number
  local cloneLinkList
  cloneLinkList=$(printf "%s" "$allCommits" \
  | grep -oP '{"fromCommit".*?"message":"'"$jiraKey"'.*?}}}' \
  | sed -e 's~.*"message":"'"$jiraKey"'.*\?"href":"\(http[^"]\+\?git\)".*~\1~g')
  
  # check if we have a list of clone links
  if [ -z "$cloneLinkList" ]; then
    echo "Could not retrieve commits from JIRA ticket $jiraKey:" >&2
	echo "$allCommits" >&2
    exit 1
  fi
  
  # execute merge of all pull-requests
  local project
  local repositorySlug
  local branchName
  local failedMerges=0
  printf '%s\n' "$cloneLinkList" | ( while IFS= read -r cloneLink
  do 
    project=$(GetProjectIdFromCloneLink "$cloneLink")
    repositorySlug=$(GetRepositorySlugFromCloneLink "$cloneLink")
	
	  # get full branch name by looking for branches that start with the JIRA ticket number
    branchName=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/branches?filterText=$jiraKey" \
	| grep -oP "(?<=\"id\":\"refs/heads/)[^\"]+")
	
	  if [ -n "$branchName" ]; then
        $(MergeAndCleanPullRequest "$userName" "$password" "$project" "$repositorySlug" "$branchName")
		[ $? -ne 0 ] && ((failedMerges++))
	  fi
  done
  echo $failedMerges )
}


# Merges all approved pull-requests of which the titles contain a specified string.
# Only pull-requests of a specified user are treated.
#
# Arguments:
#  1 - The Bitbucket user that reviews the pull-requests 
#  2 - The Bitbucket user password
#  3 - A substring of the pull-request titles that are to be merged
#
MergeAllPullRequestsWithTitle() {
  local userName="$1"
  local password="$2"
  local title="$3"

  local myApprovedPullRequests
  myApprovedPullRequests=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/dashboard/pull-requests?state=open&role=REVIEWER&participantStatus=APPROVED")

  local argumentsList  
  argumentsList=$(echo "$myApprovedPullRequests" \
  | perl -pe 's~.*?{"id":(\d+),"version":(\d+)?,"title":"[^"]*?'"$title"'[^"]*?",.*?"toRef":.*?"slug":"(.+?)",.*?"project":\{"key":"(\w+?)"~'"'\4' '\3' '\1' '\2'\n"'~gi' \
  | head -n -1)
  
  # merge all matching pull-requests
  while read arguments
  do    
    $(eval MergePullRequest "'$userName' '$password' $arguments")
  done <<< "$(echo -e "$argumentsList")"
}


# Approves a Bitbucket pull request.
#
# Arguments:
#  1 - The Bitbucket user that approves
#  2 - The Bitbucket user password
#  3 - Bitbucket Project ID
#  4 - Repository slug
#  5 - The ID of the pull request
#
ApprovePullRequest() {
  local userName="$1"
  local password="$2"
  local projectId="$3"
  local repositorySlug="$4"
  local pullRequestId="$5"
  
  if !(curl -sfX HEAD -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/pull-requests/$pullRequestId"); then
    echo "Could not approve pull-request '$projectId/$repositorySlug/$pullRequestId': The pull-request does not exist!" >&2
    exit 1
  fi
  
  local userSlug
  userSlug=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/pull-requests/$pullRequestId/participants/" \
            | grep -oP '"name":"'"$userName"'",.*?"slug":"[^"]+"' \
            | grep -oP '(?<="slug":")[^"]+')
  if [ -z "$userSlug" ]; then
    echo "Could not approve pull-request '$projectId/$repositorySlug/$pullRequestId': $userName is not a reviewer!" >&2
    exit 1
  fi
  
  local response
  response=$(curl -sfX PUT -u "$userName:$password" -H "Content-Type: application/json" -d '{
	  "status": "APPROVED"
  }' "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/pull-requests/$pullRequestId/participants/$userSlug")
  
  if [ $? -eq 0 ]; then
    echo "User $userName approved pull-request $projectId/$repositorySlug/$pullRequestId!" >&2
  else
    echo "Could not approve pull-request '$projectId/$repositorySlug/$pullRequestId': Reason unknown!" >&2
    exit 1
  fi
}


# Approves all pull-requests of which the titles contain a specified string.
# Only pull-requests of a specified user are treated.
#
# Arguments:
#  1 - The Bitbucket user that reviews the pull-requests 
#  2 - The Bitbucket user password
#  3 - A substring of the pull-request titles that are to be approved
#
ApproveAllPullRequestsWithTitle() {
  local userName="$1"
  local password="$2"
  local title="$3"

  local myOpenPullRequests
  myOpenPullRequests=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/dashboard/pull-requests?state=open&role=REVIEWER&participantStatus=UNAPPROVED")

  local argumentsList  
  argumentsList=$(echo "$myOpenPullRequests" \
  | perl -pe 's~.*?{"id":(\d+),"version":\d+?,"title":"[^"]*?'"$title"'[^"]*?",.*?"toRef":.*?"slug":"(.+?)",.*?"project":\{"key":"(\w+?)"~'"'\3' '\2' '\1'\n"'~gi' \
  | head -n -1)
  
  # approve all matching pull-requests
  while read arguments
  do
    $(eval ApprovePullRequest "'$userName' '$password' $arguments")
  done <<< "$(echo -e "$argumentsList")"
}


# Requests and returns a JSON object containing information about a pull request.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the identifier of the pull request
#
GetPullRequestInfoJson() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local pullRequestId="$5"
  
  echo $(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId)
}


# Returns the version of a pull request by parsing a JSON object of pull request information.
#  Arguments:
#  1 - a JSON string created by calling GetPullRequestInfoJson()
#
GetVersionFromPullRequestInfoJson() {
  local pullRequestInfo="$1"
  echo "$pullRequestInfo" | grep -oP '(?<="version":)\d+'
}


# Returns the current status of a pull request by parsing a JSON object of pull request information.
#  Arguments:
#  1 - a JSON string created by calling GetPullRequestInfoJson()
#
GetStatusFromPullRequestInfoJson() {
  local pullRequestInfo="$1"
  
  local reviewerInfo
  reviewerInfo=${pullRequestInfo#*\"reviewers\":\[}
  reviewerInfo=${reviewerInfo%%\],\"participants\":\[}
  
  # is the request already merged ? 
  local mergedStatus
  mergedStatus=$(echo "$pullRequestInfo" | grep -o '"state":"MERGED","open":false,')
  
  # did any reviewer set the status to 'NEEDS_WORK' ?
  local needsWorkStatus
  needsWorkStatus=$(echo "$reviewerInfo" | grep -o '"status":"NEEDS_WORK"')

  # at least one reviewer set the status to 'APPROVED'
  local approvedStatus
  approvedStatus=$(echo "$reviewerInfo" | grep -o '"status":"APPROVED"')
  
  if [ -n "$mergedStatus" ]; then
    echo "MERGED"
  elif [ -z "$needsWorkStatus" ] && [ -n "$approvedStatus" ]; then
    echo "APPROVED"
  else
    echo "NEEDS_WORK"
  fi
}


# Requests the full name of a BitBucket project.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#
GetBitBucketProjectName() {
  local userName="$1"
  local password="$2"
  local project="$3"
  
  local response
  response=$(curl -sX GET -u "$userName:$password" https://code.gerdi-project.de/rest/api/latest/projects/$project/)
  echo "$response" | grep -oP "(?<=\"name\":\")[^\"]+"
}


# Retrieves a list of all relative file paths of files that have been added in a specified commit.
# Renamed files are NOT listed.
#
# Arguments:
#  1 - the commit hash of the commit that possibly added new files
#  2 - the path to the targeted local git directory (default: current directory)
#
GetNewFilesOfCommit() {
  local commitId="${1:0:7}"
  local gitDir="${2-.}"
  
  local diff
  diff=$((cd "$gitDir" && git diff $commitId~ $commitId) \
      || (cd "$gitDir" && git show $commitId))
  echo "$diff" | tr '\n' '\t' | grep -oP '(?<=diff --git a/)([^\t]+)(?= b/\1\tnew file mode)'
}


# Retrieves a list of all relative file paths of files that have been changed in a specified commit.
# Renamed files are listed with their new name.
#
# Arguments:
#  1 - the commit hash of the commit that possibly changed files
#  2 - the path to the targeted local git directory (default: current directory)
#
GetChangedFilesOfCommit() {
  local commitId="${1:0:7}"
  local gitDir="${2-.}"
  
  local diff
  diff=$((cd "$gitDir" && git diff $commitId~ $commitId) \
      || (cd "$gitDir" && git show $commitId))
  echo "$diff" | tr '\n' '\t' | grep -oP '(?<= b/)[^\t]+(?=\tindex )'
}


# Retrieves a list of all relative file paths of files that have been deleted in a specified commit.
# Renamed files are NOT listed.
#
# Arguments:
#  1 - the commit hash of the commit that possibly deleted files
#  2 - the path to the targeted local git directory (default: current directory)
#
GetDeletedFilesOfCommit() {
  local commitId="${1:0:7}"
  local gitDir="${2-.}"
  
  local diff
  diff=$((cd "$gitDir" && git diff $commitId~ $commitId) \
      || (cd "$gitDir" && git show $commitId))
  echo "$diff" | tr '\n' '\t' | grep -oP '(?<=diff --git a/)([^\t]+)(?= b/\1\tdeleted file mode)'
}


# Adds read permission of a BitBucket repository to a specified user.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the Bitbucket user name of the user for who the permissions will be granted
AddReadPermissionForRepository() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local targetUser="$5"

  echo "Adding read permission to repository '$project/$repositorySlug' for user '$targetUser'." >&2
  echo $(curl -sX PUT -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/permissions/users?name=$targetUser&permission=REPO_READ") >&2
}


# Adds write permission of a BitBucket repository to a specified user.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the Bitbucket user name of the user for who the permissions will be granted
AddWritePermissionForRepository() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local targetUser="$5"
  
  echo "Adding write permission to repository '$project/$repositorySlug' for user '$targetUser'." >&2
  echo $(curl -sX PUT -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/permissions/users?name=$targetUser&permission=REPO_WRITE") >&2
}
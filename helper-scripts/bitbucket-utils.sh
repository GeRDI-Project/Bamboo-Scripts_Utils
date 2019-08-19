#!/bin/bash

# Copyright © 2019 Robin Weiss (http://www.gerdi-project.de/)
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

# This script offers helper functions that concern Atlassian Bitbucket of GeRDI.

# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh

# Creates a new empty Git repository.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project in which the repository is created
#  4 - a human readable name of the repository
#
CreateBitbucketRepository() {
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
DeleteBitbucketRepository() {
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


# Retrieves a list of matching tags from a Bitbucket repository.
#
# Arguments:
#  1 - Bitbucket Project ID
#  2 - Repository slug
#  3 - A substring of the tags to be retrieved (optional)
#
GetBitbucketTags() {
  local projectId="$1"
  local repositorySlug="$2"
  local tagFilter="${3-}"
  GetJoinedAtlassianResponse "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$repositorySlug/tags/?filterText=$tagFilter&orderBy=MODIFICATION" \
    | grep -oP '(?<="displayId":")[^"]+'
}


# Retrieves the newest version tag of a BitBucket repository.
#
# Arguments:
#  1 - Bitbucket Project ID
#  2 - Repository slug
#  3 - the branch that is checked (optional, default: master)
#
GetLatestBitbucketVersionTag() {
  local projectId="$1"
  local repositorySlug="$2"
  local branch="${3-master}"
  
  if [ "$branch" = "production" ]; then
    local releaseVersions=$(GetBitbucketTags "$projectId" "$repositorySlug" \
      | grep -P "^^\d+\.\d+\.\d+$")
	  
    local highestMajor
    highestMajor=$(echo "$releaseVersions" \
	  | grep -oP "^^\d+" | sort -g | tail -n1)
  
    local highestMinor
    highestMinor=$(echo "$releaseVersions" \
      | grep -oP "(?<=^^$highestMajor\.)\d+" | sort -g | tail -n1)
  
    local highestBugFix
    highestBugFix=$(echo "$versionList" \
      | grep -oP "(?<=^^$highestMajor\.$highestMinor\.)\d+" | sort -g | tail -n1)
	  
    echo "$highestMajor.$highestMinor.$highestBugFix"

  else
    # get the version from the latest Bitbucket tag
    local tagPrefix=""
    if [ "$branch" = "stage" ]; then
      tagPrefix="$bamboo_STAGING_VERSION-rc"
    else
      tagPrefix="$bamboo_TEST_VERSION-test"
    fi  
  
    local latestBuildNumber
    latestBuildNumber=$(GetBitbucketTags "$projectId" "$repositorySlug" "$tagPrefix" \
      | grep -oP "(?<=$tagPrefix)\d+" \
      | sort -g \
      | tail -n1)
  
    echo "$tagPrefix$latestBuildNumber"
  fi
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


# Checks if a remote branch of a non-checked-out BitBucket repository exists and
# creates one out of the latest commit of a specified branch, if it does not exist.
#  Arguments:
#   1 - Bitbucket user name
#   2 - Bitbucket user password
#   3 - Bitbucket Project ID
#   4 - Repository slug
#   5 - The name of the branch that is to be checked
#   6 - The name of the branch from which the new branch is to be created (optional, default: master)
#
CreateBitbucketBranch() {
  local userName="$1"
  local password="$2"
  local project="$3"
  local repositorySlug="$4"
  local branchName="$5"
  local sourceBranchName="${6-master}"
  
  local response
  response=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/latest/projects/$project/repos/$repositorySlug/branches/?filterText=$branchName")
  
  # make sure that no branch with the same name exists
  if ! $(echo "$response" | grep -q "\"id\":\"refs/heads/$branchName\""); then
    local revision
	revision=$(curl -sX GET -u "$userName:$password" "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/branches/?filterText=$sourceBranchName"\
	          | grep -oP "(?<=\"id\":\"refs/heads/$sourceBranchName\",\"displayId\":\"$sourceBranchName\",\"type\":\"BRANCH\",\"latestCommit\":\")[^\"]+")
			  
    echo "Creating Bitbucket branch '$branchName' from '$sourceBranchName' for repository '$project/$repositorySlug', revision '$revision'." >&2
	
    response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
      "name": "'"$branchName"'",
      "startPoint": "'"$revision"'",
      "message": "This branch was created by a Bamboo executed script."
    }' "https://code.gerdi-project.de/rest/api/1.0/projects/$project/repos/$repositorySlug/branches/")
  fi
}


# Removes a branch from a Git repository.
#  Arguments:
#  1 - a Bitbucket user name
#  2 - the login password that belongs to argument 1
#  3 - the ID of the project to which the repository belongs
#  4 - the identifier of the repository
#  5 - the identifier of the branch that is to be deleted
#
DeleteBitbucketBranch() {
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
  
  # check if there are pull requests for the specified source branch
  if $(echo "$allPullRequests" | grep -q '"fromRef":{"id":"refs/heads/'"$branchName"); then
    pullRequestId=$(echo "$allPullRequests" \
      | grep -oP '{"id":[^{]+?(?="fromRef":{"id":"refs/heads/'"$branchName)" \
      | grep -oP '(?<="id":)[0-9]+' \
      | head -n 1)
  else
    pullRequestId=""
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
  
  if [ $? -eq 0 ]; then
    echo "Merged pull-request: https://code.gerdi-project.de/projects/$project/repos/$repositorySlug" >&2
  else
    echo "Could not merge pull-request: https://code.gerdi-project.de/projects/$project/repos/$repositorySlug" >&2
  fi
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
    DeleteBitbucketBranch "$userName" "$password" "$project" "$repositorySlug" "$branchName"
	
  elif [ "$pullRequestStatus" = "APPROVED" ]; then
    echo "Merging https://code.gerdi-project.de/projects/$project/repos/$repositorySlug/pull-requests/$pullRequestId/" >&2
	
	local pullRequestVersion
    pullRequestVersion=$(GetVersionFromPullRequestInfoJson "$pullRequestInfoJson")
	
    MergePullRequest "$userName" "$password" "$project" "$repositorySlug" "$pullRequestId" "$pullRequestVersion" >&2
    DeleteBitbucketBranch "$userName" "$password" "$project" "$repositorySlug" "$branchName"
	
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
  | grep -oP '(?<={"href":")http[^"]*?\.git(?=")' \
  | sort -u)
  
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
	
	# get full branch name by looking for branches that contain the JIRA ticket number
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
  
  if [ -z "$argumentsList" ]; then
    echo "No pull-requests with title '$title' to merge!" >&2
  else
    # merge all matching pull-requests
    echo "Merging all Pull-requests with title: $title" >&2
    while read arguments
    do    
      eval MergePullRequest "'$userName' '$password' $arguments" >&2
    done <<< "$(echo -e "$argumentsList")"
  fi
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
  
  if [ -z "$argumentsList" ]; then
    echo "No pull-requests with title '$title' to approve!" >&2
	exit 0
  else
    # approve all matching pull-requests
    echo "Approving all Pull-requests with title: $title" >&2
    while read arguments
    do
      echo $(eval ApprovePullRequest "'$userName' '$password' $arguments") >&2
    done <<< "$(echo -e "$argumentsList")"
  fi
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


# Checks if a specified repository contains a Dockerfile that is derived from the OAI-PMH
# harvester image. Exits with 1 if the repository cannot be reached, or the Dockerfile of
# the project is not derived from the OAI-PMH image.
#  Arguments:
#  1 - the project id of the checked repository
#  2 - the repository slug of the checked repository
#  3 - a username for Basic Authentication (optional)
#  4 - a password for Basic Authentication (optional)
#
IsOaiPmhHarvesterRepository() {
  local projectId="$1"
  local slug="$2"
  local userName="${3-}"
  local password="${4-}"
    
  local auth=""
  if [ -n "$userName" ]; then
    auth="-u $userName:$password"
  fi
  
  # read DockerFile of repository
  local countOaiPmhParents=$(curl -sfX GET $auth "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$slug/browse/Dockerfile?raw&at=refs%2Fheads%2Fmaster" \
        | grep -c "FROM docker-registry\.gerdi\.research\.lrz\.de:5043/harvest/oai-pmh:")

  if [ "$countOaiPmhParents" -eq "0" ]; then
    exit 1
  fi  
}


# Checks if a specified repository contains a pom.xml.
# Exits with 1 if the repository cannot be reached, or the pom.xml is missing.
#  Arguments:
#  1 - the project id of the checked repository
#  2 - the repository slug of the checked repository
#  3 - a username for Basic Authentication (optional)
#  4 - a password for Basic Authentication (optional)
#
IsMavenizedRepository() {
  local projectId="$1"
  local slug="$2"
  local userName="${3-}"
  local password="${4-}"
    
  local auth=""
  if [ -n "$userName" ]; then
    auth="-u $userName:$password"
  fi
  
  # check if pom.xml exists in repository
  local response
  response=$(curl -sfI $auth "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$slug/browse/pom.xml?raw&at=refs%2Fheads%2Fmaster")
  if [ $? -ne 0 ]; then
    exit 1
  fi
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
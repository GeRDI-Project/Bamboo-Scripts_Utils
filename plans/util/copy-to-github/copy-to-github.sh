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

# This script can copy the master branches of a list of Bitbucket clone links
# and/or projects to GitHub. If a repository was already copied like this,
# it is updated to the latest master revision instead.

# treat unset variables as an error when substituting
set -u

source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/misc-utils.sh
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Checks if a repository with a specified name exists on GitHub.
#
# Arguments:
#  1 - the GitHub owner of the repository
#  2 - the name of the repository
#
HasRepositoryOnGitHub() {
  local gitHubUserName="$1"
  local repositoryName="$2"
  
  # look for the repository name in the GitHub repository
  curl -sX GET "https://api.github.com/users/$gitHubUserName/repos" \
  | grep -q '"name": "'"$repositoryName"
}


# Retrieves the git URL of a GitHub repository.
#
# Arguments:
#  1 - the GitHub owner of the repository
#  2 - the name of the repository
#
GetGitHubRepositoryUrl() {
  local gitHubUserName="$1"
  local repositoryName="$2"
  
  # get GitHub repository info
  local gitHubResponse
  gitHubResponse=$(curl -sX GET "https://api.github.com/users/$gitHubUserName/repos")
  
  # extract the URL
  local gitHubUrl
  gitHubUrl=${gitHubResponse#*\"name\": \"$repositoryName\",}
  gitHubUrl=${gitHubUrl#*\"git_url\": \"}
  gitHubUrl=${gitHubUrl%%\"*}
  
  echo "$gitHubUrl"
}


# Creates a valid GitHub repository name using Bitbucket information.
#
# Arguments:
#  1 - the repository name in Bitbucket
#  2 - the project name in Bitbucket
#
GetGitHubRepositoryName() {
  local bitbucketProjectName="$1"
  local bitbucketRepoName="$2"
  
  bitbucketProjectName=$(echo "$bitbucketProjectName" | tr ' ' '-' | tr '_' '-')
  bitbucketRepoName=$(echo "$bitbucketRepoName" | tr ' ' '-' | tr '_' '-')
  
  echo "$bitbucketRepoName"_"$bitbucketProjectName"
}


# Creates or updates a GitHub repository, mirroring an existing
# Bitbucket GeRDI repository.
#
# Arguments:
#  1 - a Git clone link of the source Bitbucket repository
#  2 - an Atlassian Bitbucket user name
#  3 - the password of the Bitbucket user
#  4 - a GitHub user name
#  5 - the password of the GitHub user
#
AddGitHubRemoteToBitbucketRepository() {
  local bitbucketCloneUrl="$1"
  local bitbucketUserName="$2"
  local bitbucketPassword="$3"
  local gitHubUserName="$4"
  local gitHubPassword="$5"
  
  # get Bitbucket project ID and slug
  local bitbucketProject
  bitbucketProject=$(GetProjectIdFromCloneLink "$bitbucketCloneUrl")
  local bitbucketSlug
  bitbucketSlug=$(GetRepositorySlugFromCloneLink "$bitbucketCloneUrl")

  # get Bitbucket repository info
  local bitbucketResponse
  bitbucketResponse=$(curl -sX GET "https://code.gerdi-project.de/rest/api/1.0/projects/$bitbucketProject/repos/$bitbucketSlug")
  
  # retrieve repository name
  local repoName
  repoName=$(echo "$bitbucketResponse" | grep -oP '(?<="name":")[^"]+(?=","scmId":)')
  
  # retrieve project name
  local projectName
  projectName=$(echo "$bitbucketResponse" | grep -oP '(?<="name":")[^"]+(?=","description":)')
  
  # create GitHub repository name
  local gitHubRepoName
  gitHubRepoName=$(GetGitHubRepositoryName "$projectName" "$repoName")
  
  local gitHubUrl
  
  # check if GitHub repository exists already
  if $(HasRepositoryOnGitHub "$gitHubUserName" "$gitHubRepoName"); then
    gitHubUrl=$(GetGitHubRepositoryUrl "$gitHubUserName" "$gitHubRepoName")
	
	if [ -n "$gitHubUrl" ]; then
	  echo "Found existing GitHub repository '$gitHubUrl'. Updating..." >&2
	else
	  echo "Could not retrieve GitHub repository URL from '$gitHubRepoName'!" >&2
	  exit 1
	fi	
  else
    # create repository on GitHub
    local gitHubResponse
    gitHubResponse=$(curl -sX POST -u "$gitHubUserName:$gitHubPassword" -H "Content-Type: application/json" -d '{
      "name": "'"$gitHubRepoName"'",
      "homepage": "https://gerdi-project.eu",
      "private": false,
      "has_issues": false,
      "has_projects": false,
      "has_wiki": false
    }' "https://api.github.com/user/repos")

    # retrieve URL from GitHub repository
    gitHubUrl=$(echo "$gitHubResponse" | grep -oP '(?<="git_url": ")[^"]+')
    
	if [ -n "$gitHubUrl" ]; then
	  echo "Created GitHub repository '$gitHubUrl'. Adding data..." >&2
	else
	  echo "Could not create GitHub repository '$gitHubRepoName':" >&2
	  echo -e "$gitHubResponse" >&2
	  exit 1
	fi
  fi
  
  # add credentials to the GitHub URL
  gitHubUrl="https://$gitHubUserName:$gitHubPassword@${gitHubUrl#git://}"
  
  # clone Bitbucket repository
  mkdir tempRepo
  cd tempRepo
  CloneGitRepository \
	"$bitbucketUserName" \
	"$bitbucketPassword" \
	"$bitbucketProject" \
	"$bitbucketSlug"

  # add remote to GitHub repository
  git remote add github "$gitHubUrl" >&2
  git remote -v >&2
  git push -u github master >&2
  
  # delete cloned Bitbucket repository files
  cd ..
  rm -rf tempRepo
}


Main() {
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "projectsAndCloneLinks"

  # get and verify Atlassian credentials
  local bitbucketUserName
  bitbucketUserName=$(GetBambooUserName)
  local bitbucketPassword
  bitbucketPassword=$(GetValueOfPlanVariable "atlassianPassword")
  ExitIfAtlassianCredentialsWrong "$bitbucketUserName" "$bitbucketPassword"
  
  # get other plan variables
  local gitHubUserName
  gitHubUserName=$(GetValueOfPlanVariable "gitHubUserName")
  local gitHubPassword
  gitHubPassword=$(GetValueOfPlanVariable "gitHubPassword")
  local projectsAndCloneLinks
  projectsAndCloneLinks=$(GetValueOfPlanVariable "projectsAndCloneLinks")
  
  # define a list of arguments to be used by the 'AddGitHubRemoteToBitbucketRepository' function
  local repositoryArguments
  repositoryArguments="'$bitbucketUserName' '$bitbucketPassword' '$gitHubUserName' '$gitHubPassword'"
  
  ProcessListOfProjectsAndRepositories \
    "$bitbucketUserName" \
    "$bitbucketPassword" \
    "$projectsAndCloneLinks" \
    "AddGitHubRemoteToBitbucketRepository" \
    "$repositoryArguments"  
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
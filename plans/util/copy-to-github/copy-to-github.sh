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


# Retrieves the git URL of a GitHub repository.
#
# Arguments:
#  1 - the GitHub owner of the repository
#  2 - the name of the repository
#  3 - the GitHub Organization of the repository (optional)
#
GetGitHubRepositoryUrl() {
  local gitHubUserName="$1"
  local repositoryName="$2"
  local gitHubOrganizationName="${3-}"
  
  local gitHubUrl
  if [ -n "$gitHubOrganizationName" ]; then
    gitHubUrl="https://api.github.com/orgs/$gitHubOrganizationName/repos"
  else
    gitHubUrl="https://api.github.com/users/$gitHubUserName/repos"
  fi
  
  # local function for retrieving the URL
  GetRepositoryUrl() {
    local repoUrl
    repoUrl=${1#*\"name\": \"$repositoryName\",}
	
	if ! [ "$1" = "$repoUrl" ]; then
      repoUrl=${repoUrl#*\"git_url\": \"}
      repoUrl=${repoUrl%%\"*}
      echo "$repoUrl"
	  exit 0
	fi
  }
  
  IterateGitHubRepositories "GetRepositoryUrl" "$gitHubUrl"
}


# Iterates all paginated responses of a specified GitHub URL.
#
# Arguments:
#  1 - the name of the function that is to be executed on each response
#  2 - a GitHub API URL that supports pagination
#  3 - the starting page number (optional)
#
IterateGitHubRepositories() {
  local functionName="$1"
  local gitHubUrl="$2"
  local page="${3-1}"

  local gitHubResponse=$(curl -sX GET "$gitHubUrl?page=$page")

  if $(echo "$gitHubResponse" | grep -q '"id":'); then
    eval "$functionName" "'$gitHubResponse'"
    IterateGitHubRepositories "$functionName" "$gitHubUrl" $(expr $page + 1)
  fi
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
  local gitHubOrganization="${6-}"
  
  # get Bitbucket project ID and slug
  local bitbucketProject
  bitbucketProject=$(GetProjectIdFromCloneLink "$bitbucketCloneUrl")
  local bitbucketSlug
  bitbucketSlug=$(GetRepositorySlugFromCloneLink "$bitbucketCloneUrl")

  # get Bitbucket repository info
  local bitbucketResponse
  bitbucketResponse=$(curl -sX GET -u "$bitbucketUserName:$bitbucketPassword" "https://code.gerdi-project.de/rest/api/1.0/projects/$bitbucketProject/repos/$bitbucketSlug")
  
  # retrieve repository name
  local repoName
  repoName=${bitbucketResponse#*\"name\":\"}
  repoName=${repoName%%\"*}
  
  # retrieve project name
  local projectName
  projectName=${bitbucketResponse#*\"project\":\{}
  projectName=${projectName#*\"name\":\"}
  projectName=${projectName%%\"*}
  
  if [ -z "$repoName" ] || [ -z "$projectName" ]; then
	  echo "Could not retrieve project or repository name from: https://code.gerdi-project.de/rest/api/1.0/projects/$bitbucketProject/repos/$bitbucketSlug" >&2
	  echo "The '$bitbucketUserName' Bitbucket user may lack permissions!" >&2
      exit 1
  fi
  
  # create GitHub repository name
  local gitHubRepoName
  gitHubRepoName=$(GetGitHubRepositoryName "$projectName" "$repoName")
  
  local gitHubUrl
  
  # check if GitHub repository exists already
  gitHubUrl=$(GetGitHubRepositoryUrl "$gitHubUserName" "$gitHubRepoName" "$gitHubOrganization")
  if [ -n "$gitHubUrl" ]; then
	  echo "Found existing GitHub repository '$gitHubUrl'. Updating..." >&2
  else
    local gitHubRequestUrl
	if [ -n "$gitHubOrganization" ]; then
	  gitHubRequestUrl="https://api.github.com/orgs/$gitHubOrganization/repos"	
	else
	  gitHubRequestUrl="https://api.github.com/user/repos"
	fi
	
    # create repository on GitHub
    local gitHubResponse
    gitHubResponse=$(curl -sX POST -u "$gitHubUserName:$gitHubPassword" -H "Content-Type: application/json" -d '{
      "name": "'"$gitHubRepoName"'",
      "homepage": "https://gerdi-project.eu",
      "private": false,
      "has_issues": false,
      "has_projects": false,
      "has_wiki": false
    }' "$gitHubRequestUrl")

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
  ExitIfPlanVariableIsMissing "gitHubUserName"
  ExitIfPlanVariableIsMissing "gitHubPassword"
  ExitIfPlanVariableIsMissing "projectsAndCloneLinks"
  ExitIfPlanVariableIsMissing "gitHubOrganization"

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
  
  local gitHubOrganization
  gitHubOrganization=$(GetValueOfPlanVariable "gitHubOrganization")
  
  # define a list of arguments to be used by the 'AddGitHubRemoteToBitbucketRepository' function
  local repositoryArguments
  repositoryArguments="'$bitbucketUserName' '$bitbucketPassword' '$gitHubUserName' '$gitHubPassword' '$gitHubOrganization'"
  
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
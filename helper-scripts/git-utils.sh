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

# This script offers helper functions that concern Git.


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


# Creates a remote Git branch of the current repository.
#  Arguments:
#  1 - the name of the branch
#
CreateBranch() {
  local branchName="$1"
  echo $(git checkout -b $branchName) >&2
  echo $(git push -q --set-upstream origin $branchName) >&2
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
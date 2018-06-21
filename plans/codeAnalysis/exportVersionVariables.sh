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

# This script extracts the Maven version, and it assembles the version tag which is derived from global
# Bamboo variables. Both versions are stored in a file which can then be exported to a Deployment job
# via the "Inject Bamboo variables" task
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#
# Arguments:
#  1 - the file name of the file which is generated to be exported via the "Inject Bamboo variables" task

# treat unset variables as an error when substituting
set -u

#########################
#  FUNCTION DEFINITIONS #
#########################

# Retrieves the highest number suffix of a git tag that starts with a specified
# prefix, and increments it before returning it. If no tags with the specified
# prefix exist, 1 is returned instead
#
GetBuildNumber() {
  local tagPrefix="$1"
  
  local previousTag
  previousTag=$(git tag --sort="taggerdate" -l "$tagPrefix*" | tail -n1)
  
  if [ "$previousTag" != "" ]; then
    echo $(expr 1 + ${previousTag#$tagPrefix})
  else
    echo 1
  fi
}


# Retrieves the next version tag by checking the current branch and the value
# of global Bamboo variables.
#
GetTagVersion() {
  # get branch name
  local currentBranch
  currentBranch=$(git branch --points-at HEAD)
  currentBranch=${currentBranch:2}

  # define local variables
  local tagPrefix
  tagPrefix=""
  local buildNumber
  buildNumber=""
  
  # define the tagging prefix, based on the current branch
  # define build number, based on tags
  if [ "$currentBranch" = "master" ]; then
    tagPrefix="$bamboo_TEST_VERSION-test"
    buildNumber=$(GetBuildNumber "$tagPrefix")
  
  elif [ "$currentBranch" = "stage" ]; then
    tagPrefix="$bamboo_STAGING_VERSION-rc"
    buildNumber=$(GetBuildNumber "$tagPrefix")
  
  elif [ "$currentBranch" = "production" ]; then
    tagPrefix="$bamboo_PRODUCTION_VERSION"
    buildNumber=""
  fi

  if [ "$tagPrefix" != "" ]; then
    echo "$tagPrefix$buildNumber"
  else
    echo ""
  fi
}


# Retrieves the version of a pom.xml.
#
GetMavenVersion() {
  local mavenVersion
  mavenVersion=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' \
  --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  if [ "$?" -ne "0" ]; then
    mavenVersion=""
  fi
  echo "$mavenVersion"
}


# The main function of this script.
#
Main() {
  local exportFilePath="$1"

  if [ -z "$exportFilePath" ]; then
    echo 'You must specify the name of the exported variables file as the first argument of this script! 
It must match the "Inject Bamboo variables" task which is to be executed after this script!' >&2
    exit 1
  else
    readonly exportFilePath
  fi

  rm -f "$exportFilePath"
  echo -e "maven.version=$(GetMavenVersion)\ntag.version=$(GetTagVersion)"  >> "$exportFilePath"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$1"
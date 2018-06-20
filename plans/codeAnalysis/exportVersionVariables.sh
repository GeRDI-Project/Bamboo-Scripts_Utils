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

# This script extracts the Maven version, and assembles the version tag which is derived from global
# Bamboo variables. Both versions are stored in a file which can then be exported to a Deployment job
# via the "Inject Bamboo variables" task
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#
# Arguments:
#  1 - the file name of the file which is generated to be exported via the "Inject Bamboo variables" task

# Retrieves the next version tag by checking the current branch and the value
# of global Bamboo variables.
#
GetTagVersion() {
  # get branch name
  currentBranch=$(git branch --points-at HEAD)
  currentBranch=${currentBranch:2}

  # define the tagging prefix
  if [ "$currentBranch" = "master" ]; then
    tagPrefix="$bamboo_TEST_VERSION-test"
    buildNumber=1  
  
  elif [ "$currentBranch" = "stage" ]; then
    tagPrefix="$bamboo_STAGING_VERSION-rc"
    buildNumber=1
  
  elif [ "$currentBranch" = "production" ]; then
    tagPrefix="$bamboo_PRODUCTION_VERSION"
    buildNumber=""
  fi

  if [ "$tagPrefix" != "" ]; then
    # calculate build number of this release version and environment
    if [ "$buildNumber" = "1" ]; then
      previousTag=$(git tag --sort="taggerdate" -l "$tagPrefix*" | tail -n1)
      echo "prevTags: $(git tag --sort="taggerdate")" >&2
      echo "prevTag: $previousTag" >&2
	  if [ "$previousTag" != "" ]; then
        buildNumber=$(expr 1 + ${previousTag#$tagPrefix})
      fi
    fi
    echo "$tagPrefix$buildNumber"
  else
    echo ""
  fi
}


# Retrieves the version of a pom.xml.
#
GetMavenVersion() {
  mavenVersion=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  if [ "$?" -ne "0" ]; then
    mavenVersion=""
  fi
  echo "$mavenVersion"
}

exportFilePath="$1"

if [ "$exportFilePath" = "" ]; then
  echo 'You must specify the name of the exported variables file as the first argument of this script! 
It must match the "Inject Bamboo variables" task which is to be executed after this script!' >&2
  exit 1
fi

rm -f "$exportFilePath"
echo -e "maven.version=$(GetMavenVersion)\ntag.version=$(GetTagVersion)"  >> "$exportFilePath"
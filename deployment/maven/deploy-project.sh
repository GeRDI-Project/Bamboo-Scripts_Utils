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

# This script is called by Bamboo deployment jobs in order to deploy Maven
# projects to Sonatype or Maven Central.
#
# Arguments:
#  1 - the path to the pom.xml that is to be deployed


# treat unset variables as an error when substituting
set -u

# load helper scripts
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Attempts to deploy a Maven project without sanity checks.
#
# Arguments:
#  1 - a file path to a pom.xml or a Maven project folder
#
DeployMavenSnapshot() {
  local pomXmlPath="$2"
  mvn clean deploy -Ddeploy -f"$pomXmlPath"
}


# Attempts to deploy a Maven project while making sure that it does
# not contain SNAPSHOT versions.
#
# Arguments:
#  1 - a file path to a pom.xml or a Maven project folder
#  2 - the project version that is to be deployed
#
DeployMavenRelease() {
  local pomXmlPath="$1"
  local version="$2"

  if $(HasSnapshotVersions "$pomXmlPath"); then
    echo "Cannot deploy'$pomXmlPath', because it contains SNAPSHOT dependencies!" >&2
    exit 1
  fi
  
  local artifactId
  artifactId=$(GetPomValue "project.artifactId" "$pomXmlPath")
  
  local isDeployed
  isDeployed=$(IsMavenVersionDeployed "$artifactId" "$version")
  
  if $isDeployed; then
    echo "Cannot deploy $artifactId $version, because it was already released!" >&2
    exit 1
  fi
  
  mvn clean deploy -Ddeploy -Prelease -f"$pomXmlPath"
}


# The main function that is called by this script.
#
Main() {
  ExitIfDeployEnvironmentDoesNotMatchBranch
 
  # exit if not a maven project
  local pomXmlPath=$(CompletePomPath "$1")
  if [ ! -f "$pomXmlPath" ]; then
    echo "Cannot deploy Maven project at '$pomXmlPath' because the path does not exist!" >&2
    exit 1
  fi
  
  local environment
  environment=$(GetDeployEnvironmentName)
  
  local projectVersion
  projectVersion=$(GetPomValue "project.version" "$pomXmlPath")
  
  if [ "$environment" = "test" ]; then
    if $(echo "$projectVersion" | grep -q "\-SNAPSHOT\$"); then
      DeployMavenSnapshot "$pomXmlPath"
    else
      DeployMavenRelease "$pomXmlPath" "$projectVersion"
    fi
    
  elif [ -n "$environment" ]; then
    if $(echo "$projectVersion" | grep -q "\-SNAPSHOT\$"); then
      echo "Maven Projects must not have SNAPSHOT versions in staging or production!" >&2
      exit 1
    else
      DeployMavenRelease "$pomXmlPath" "$projectVersion"
    fi
  fi
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
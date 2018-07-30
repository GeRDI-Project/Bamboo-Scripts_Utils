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

# This script is called by Bamboo CI jobs in order to fail the job
# if the pom.xml contains SNAPSHOT versions on staging or production environments.
#
# Arguments:
#  1 - the path to the pom.xml that is to be deployed (optional)


# do not treat unset variables as an error when substituting, because the argument is optional
# set -u

# load helper scripts
source ./scripts/helper-scripts/maven-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# The main function that is called by this script.
#
Main() {
  local pomXmlPath=$(GetPomXmlPath "$1")
  
  local currentBranch
  currentBranch="$bamboo_planRepository_1_branchName"
  
  if $(HasSnapshotVersions "$pomXmlPath"); then
    if [ "$currentBranch" = "stage" ] || [ "$currentBranch" = "production" ]; then
	  echo "The '$pomXmlPath' contains SNAPSHOT versions! These must be released!" >&2
	  exit 1
	else
	  echo "The '$pomXmlPath' contains SNAPSHOT versions! These must be released in the Staging and Production environments!" >&2
    fi 
  else
    echo "The '$pomXmlPath' contains no SNAPSHOT versions! Nice!" >&2
  fi
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
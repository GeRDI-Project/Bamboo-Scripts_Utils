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

# This script is called by some Bamboo Jobs in order to run Bamboo Specs and create plans and deployment jobs.
#
# Arguments:
#  1 - the login name of the current user
#  2 - the Atlassian password of the current user
#  3 - the name of the data provider that is to be harvested, but without spaces and special characters

# treat unset variables as an error when substituting
set -u

# load helper scripts
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/maven-utils.sh

# The main function of this script.
#
Main() {
  local atlassianUserName="$1"
  local atlassianPassword="$2"
  local providerClassName="$3"
  local project="$4"
  local repositorySlug="$5"
  
  # copy placeholder bamboo-specs
  rm -fr "bambooSpecsTemp"
  cp -r "harvesterSetup/bamboo-specs" "bambooSpecsTemp"

  # create Bamboo plans
  cd bambooSpecsTemp/plans
  echo -e $(mvn -e compile -Dexec.args="'$atlassianUserName' '$atlassianPassword' '$providerClassName' '$project' '$repositorySlug'") >&2

  # add plan branches
  local planLabel
  planLabel=$(GetPlanLabelByProjectAndName "CA" "$providerClassName-Harvester Static Analysis" "$atlassianUserName" "$atlassianPassword")
  
  # work-around for latency in bamboo job creation
  local retries=5
  while [ -z "$planLabel" ]; do
	sleep 3
    planLabel=$(GetPlanLabelByProjectAndName "CA" "$providerClassName-Harvester Static Analysis" "$atlassianUserName" "$atlassianPassword")
	
	echo "$retries : curl https://ci.gerdi-project.de/rest/api/latest/search/plans?searchTerm=$providerClassName-Harvester Static Analysis"
    echo $(curl -sX GET -u "$atlassianUserName:$atlassianPassword" "https://ci.gerdi-project.de/rest/api/latest/search/plans?searchTerm=$providerClassName-Harvester Static Analysis") >&2
	
	retries=$(expr "$retries" - 1)
	if [ -z "$planLabel" ] && [ $retries -eq 0 ]; then
      echo "Could not create plan!" >&2
	  exit 1
	fi
  done
  
  CreatePlanBranch "$planLabel" "stage" "$atlassianUserName" "$atlassianPassword"
  CreatePlanBranch "$planLabel" "production" "$atlassianUserName" "$atlassianPassword"
  
  # create Bamboo deployments
  cd ../deployments
  echo -e $(mvn -e compile -Dexec.args="'$atlassianUserName' '$atlassianPassword' '$providerClassName' '$project' '$repositorySlug'") >&2
}

Main "$@"
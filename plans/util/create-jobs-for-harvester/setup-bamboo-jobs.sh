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
  
  # copy placeholder bamboo-specs
  rm -fr "bambooSpecsTemp"
  cp -r "harvesterSetup/bamboo-specs" "bambooSpecsTemp"

  # rename placeholders for bamboo specs
  cd bambooSpecsTemp
  ./../harvesterSetup/scripts/renameSetup.sh "$providerClassName" "XXX" "XXX" "XXX" "XXX" "XXX" "XXX"
 
  # create Bamboo plans
  cd plans
  RunBambooSpecs "$atlassianUserName" "$atlassianPassword"

  # add plan branches
  local planLabel
  planLabel=$(GetPlanLabelByProjectAndName "CA" "$providerClassName Static Analysis" "$atlassianUserName" "$atlassianPassword")
  CreatePlanBranch "$planLabel" "stage" "$atlassianUserName" "$atlassianPassword"
  CreatePlanBranch "$planLabel" "production" "$atlassianUserName" "$atlassianPassword"
  
  # create Bamboo deployments
  cd ../deployments
  RunBambooSpecs "$atlassianUserName" "$atlassianPassword"
}

Main "$@"
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
 
# This script runs a specified list of Bamboo plans.
#
# Arguments:
#  1 - a comma separated list of plan keys


# treat unset variables as an error when substituting
set -u

source ./scripts/helper-scripts/bamboo-utils.sh


# Processes a list of plan labels and runs each plan on a specified branch.
#
# Arguments:
#  1 - A list of plan labels
#  2 - The plan branch name
#
StartListOfPlans() {
  local planList=$(echo "$1" | tr -d " " | tr "," "\n")
  local branch="$2"
  
  # iterate through all clone links and/or projects
  while read planLabel
  do
	StartBambooPlanBranchWithoutCredentials "$planLabel" "$branch"
  done <<< "$(echo -e "$planList")"
}


# The main function that is called by this script.
Main() {
bamboo_deploy_environment="stage"
  local planList="$1"
  local branch=$(GetDeployEnvironmentBranch)
  
  echo "Starting plans '$planList' on branch '$branch'..."
  
  StartListOfPlans "$planList" "$branch"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
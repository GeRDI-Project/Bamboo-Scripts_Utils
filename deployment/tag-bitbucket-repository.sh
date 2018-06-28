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

# This script can be called by Bamboo (Deployment) Jobs in order to tag the git commit
# that triggered the job with the tag version that is injected as a variable.
# The repository that is to be tagged must be a BitBucket repository.
#
# Arguments:
#  1 - the name of the tag that is applied to the git repository
#
# Bamboo Plan Variables:
#  bamboo_planRepository_1_repositoryUrl 
#    The ssh clone link to the first repository of the plan.
#    This should be the repository which is to be tagged.
#  bamboo_planRepository_1_revision
#    The commit hash of the commit of the plan.
#  bamboo_buildNumber
#    The plan's build number.
#  bamboo_planKey
#    The plan key of the plan that is deployed.
#

# treat unset variables as an error when substituting
set -u


#########################
#  FUNCTION DEFINITIONS #
#########################

# Assembles a BitBucket REST-API URL that can add a tag to a repository
# 
GetTagUrl() {
  local slug
  slug=${bamboo_planRepository_1_repositoryUrl%.git}
  slug=${slug##*/}

  local projectId
  projectId=${bamboo_planRepository_1_repositoryUrl%/*}
  projectId=${projectId##*/}

  echo "https://code.gerdi-project.de/rest/api/1.0/projects/$projectId/repos/$slug/tags"
}


# Assembles a JSON body that can be sent to the BitBucket REST-API in order to tag a
# repository.
#
# Arguments:
#  1 - the name of the tag that is applied to the git repository
#
GetTagBody() {
  local tagName="$1"
  
  local tagMessage="https://ci.gerdi-project.de/browse/${bamboo.planKey}-${bamboo.buildNumber}"
  
  echo '{
    "name": "'${tagName}'",
    "startPoint": "'${bamboo.planRepository.1.revision}'",
    "message": "'${tagMessage}'"
  }'
}


# The main method of this script.
#
Main() {
  local tagName="$1"
  
  local tagUrl
  tagUrl=$(GetTagUrl)

  local jsonBody
  jsonBody=$(GetTagBody "$tagName")
  curl -nsX POST -H "Content-Type: application/json" -d "$jsonBody" "$tagUrl"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
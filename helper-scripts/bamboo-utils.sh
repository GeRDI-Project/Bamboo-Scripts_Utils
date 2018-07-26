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

# This script offers helper functions that concern Atlassian Bamboo of GeRDI.


# Returns the value of a specified plan variable.
#  Arguments:
#  1 - the name of the plan variable as it appears in the Bamboo front-end
#
GetValueOfPlanVariable() {
  local internalVarName="bamboo_$1"
  echo "${!internalVarName}"
}


# Returns the user name of the one who has triggered this Bamboo job.
#
GetBambooUserName() {
  echo "$bamboo_ManualBuildTriggerReason_userName"
}


# Returns a numerical identifier of a plan branch.
#  Arguments:
#  1 - the identifier of the plan
#  2 - the string identifier of the git branch
#  3 - a Bamboo user name that has the necessary permissions for this operation
#  4 - a password for argument 3
#
GetPlanBranchId() {
  local planLabel="$1"
  local branch="$2"
  local userName="$3"
  local password="$4"
  
  local planBranchId
  planBranchId=$(curl -sX GET -u "$userName:$password" https://ci.gerdi-project.de/rest/api/latest/plan/$planLabel/branch/$branch \
                 | grep -oP "(?<=key=\"$planLabel)[^\"]+" \
                 | head -1)
				 
  if [ -z "$planBranchId" ]; then
    echo "The plan branch $planLabel/$branch does not exist!" >&2
	exit 1
  fi
  
  echo "$planBranchId"
}


# Returns a numerical identifier of a deployment job which is linked to a specified plan.
#  Arguments:
#  1 - the identifier of the linked plan
#  2 - a Bamboo user name that has the necessary permissions for this operation
#  3 - a password for argument 2
#
GetDeploymentId() {
  local planLabel="$1"
  local userName="$2"
  local password="$3"
  
  local deploymentId
  deploymentId=$(curl -sX GET -u "$userName:$password"  "https://ci.gerdi-project.de/rest/api/latest/deploy/project/forPlan?planKey=$planLabel" \
                 | grep -oP "(?<=\"id\":)\d+")

  # check if a plan with the specified label exists
  if [ -z "$deploymentId" ]; then
    echo "The plan $planLabel does not have a deployment job" >&2
  fi
  
  echo "$deploymentId"
}


# Returns the number of the latest build of a specified plan.
#  Arguments:
#  1 - the identifier of the plan
#  2 - the numerical identifier of the plan branch
#  3 - a Bamboo user name that has the necessary permissions for this operation
#  4 - a password for argument 3
#
GetLatestBambooPlanResultKey() {
  local planLabel="$1"
  local planBranchId="$2"
  local userName="$3"
  local password="$4"
  
  # check latest finished build
  local response
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json"  https://ci.gerdi-project.de/rest/api/latest/result/$planLabel$planBranchId?max-results=1)
  
  local planResultKey
  planResultKey=$(echo "$response" | grep -oP '(?<=<buildResultKey>).+(?=</buildResultKey>)')
  
  # check if a build is in progress
  local nextBuildNumber
  local nextPlanResultKey
  local httpCode
  
  if [ -n "$planResultKey" ]; then
    nextBuildNumber=${planResultKey##*-}
	nextBuildNumber=$(expr $nextBuildNumber + 1)
    nextPlanResultKey="${planResultKey%-*}-$nextBuildNumber"
	
    response=$(curl -u "$userName:$password"  -sIX HEAD "https://ci.gerdi-project.de/rest/api/latest/result/status/$nextPlanResultKey")
    httpCode=$(echo "$response" | grep -oP '(?<=HTTP/\d\.\d )\d+')
	
	if [ "$httpCode" = "200" ]; then
	  planResultKey="$nextPlanResultKey"
	fi
  fi
  
  echo "$planResultKey"
}


# Returns the environment identifier of a specified environment of a specified deployment job.
#  Arguments:
#  1 - the identifier of the deployment job
#  2 - the name of the requested environment
#  3 - a Bamboo user name that has the necessary permissions for this operation
#  4 - a password for argument 2
#
GetDeployEnvironmentId() {
  local deploymentId="$1"
  local environmentName="$2"
  local userName="$3"
  local password="$4"
  
  local response
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/project/$deploymentId)
  response=${response#*\"environments\":\[}
  
  local environmentId
  environmentId=$(echo "$response" | grep -oP "(?<=\{\"id\":)\d+(?=,.*?\"name\":\"$environmentName\")")
  
  if [ -z "$environmentId" ]; then
    echo "Could not find a 'Maven Deploy' environment for deployment project $deploymentId!" >&2
  fi
  
  echo "$environmentId"
}


# Searches for a plan with a specified name inside a specified project and
# returns the first matching plan.
#  Arguments:
#  1 - the ID of the project
#  2 - the name of the plan
#  3 - a Bamboo user name that has the necessary permissions for this operation
#  4 - a password for argument 3
#
GetPlanLabelByProjectAndName() {
  local projectId="$1"
  local planName="$2"
  local userName="$3"
  local password="$4"
  
  local response
  response=$(curl -sX GET -u "$userName:$password" "https://ci.gerdi-project.de/rest/api/latest/search/plans?searchTerm=$planName")
  echo "$response" | grep -oP "(?<=\<key\>)$projectId-.+?(?=\</key\>)" | head -n1
}


# Runs a specified Bamboo plan and returns the plan result key which serves as an identifier
# of the plan execution.
#  Arguments:
#  1 - the identifier of the plan
#  2 - a Bamboo user name that has the necessary permissions for this operation
#  3 - a password for argument 2
#
StartBambooPlan() {
  local planLabel="$1"
  local userName="$2"
  local password="$3"
  
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{}' https://ci.gerdi-project.de/rest/api/latest/queue/$planLabel?stage\&executeAllStages)
  
  local buildNumber
  buildNumber=$(echo "$response" | grep -oP '(?<=buildNumber=")\d+(?=")')
  
  # return plan result key
  if [ -z "$buildNumber" ]; then
    echo "Could not start Bamboo Plan $planLabel: $response" >&2
  else
    echo "$planLabel-$buildNumber"
  fi
}


# Waits for a specified Bamboo plan execution to be finished.
# Fails with exit code 1 if the plan failed.
#  Arguments:
#  1 - the plan result key of the execution
#  2 - a Bamboo user name that has the necessary permissions for this operation
#  3 - a password for argument 2
#
WaitForPlanToBeDone() {
  local planResultKey="$1"
  local userName="$2"
  local password="$3"
  
  echo "Waiting for plan $planResultKey to finish..." >&2
  
  # send a head-request to check if a plan result page exists
  local resultsUrl
  resultsUrl="https://ci.gerdi-project.de/rest/api/latest/result/$planResultKey"
  $(curl -sfX HEAD -u "$userName:$password" $resultsUrl)
  
  local responseCode=$?
  
  # wait 3 seconds and re-send the head-request if needed
  while [ $responseCode -ne 0 ]; do
	sleep 3
    $(curl -sfX HEAD -u "$userName:$password" $resultsUrl)
    responseCode=$?
  done
  
  # there is a small transition period during which the build state is unknown, though the job is finished:
  local buildState
  buildState=$(curl -sX GET -u "$userName:$password" $resultsUrl | grep -oP "(?<=\<buildState\>)\w+?(?=\</buildState\>)")
  
  while [ "$buildState" = "Unknown" ] || [ -z "$buildState" ]; do
    sleep 3
	buildState=$(curl -sX GET -u "$userName:$password" $resultsUrl | grep -oP "(?<=\<buildState\>)\w+?(?=\</buildState\>)")
  done
    
  # check if the plan finished successfully
  echo "Bamboo Plan $planResultKey finished with state '$buildState'!" >&2
  if [ "$buildState" != "Successful" ]; then
    exit 1
  fi
}


# Runs a specified Bamboo deployment job and returns the deployment result id which serves as an identifier
# of the deployment.
#  Arguments:
#  1 - the identifier of the deployment
#  2 - the identifier of the executed deployment environment
#  3 - the deployment version
#  4 - the plan result key of the plan from which should be deployed
#  5 - a Bamboo user name that has the necessary permissions for this operation
#  6 - a password for argument 5
#
StartBambooDeployment() {
  local deploymentId="$1"
  local environmentId="$2"
  local deploymentVersion="$3"
  local planResultKey="$4"
  local userName="$5"
  local password="$6"
  
  local requestSuffix=""
  local versionId=""
  local tries=1
  
  # build a version. if it already exists, append _(1)
  local response
  local hasError
  
  while [ -z "$versionId" ]; do  
    response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
      "planResultKey":"'"$planResultKey"'",
      "name":"'"$deploymentVersion$requestSuffix"'"
    }' https://ci.gerdi-project.de/rest/api/latest/deploy/project/$deploymentId/version)
  
    hasError=$(echo $response | grep -P "This release version is already in use, please select another.")
    if [ "${#hasError}" -eq 0 ]; then
      versionId=${response#*\{\"id\":}
      versionId=${versionId%%,*}
    else
      requestSuffix="_($tries)"
      tries=$(expr $tries + 1 )
    fi
  done
  
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/queue/deployment?environmentId=$environmentId\&versionId=$versionId)
  
  local deploymentResultId
  deploymentResultId=$(echo "$response" | grep -oP '(?<="deploymentResultId":)\d+(?=,)')
  
  # return plan result key
  if [ -z "$deploymentResultId" ]; then
    echo "Could not start Bamboo Plan $planLabel: $response" >&2
  fi
  echo "$deploymentResultId"
}


# Waits for a specified Bamboo deployment job to be finished.
# Fails with exit code 1 if the deployment failed.
#  Arguments:
#  1 - the deployment result id of the execution
#  2 - a Bamboo user name that has the necessary permissions for this operation
#  3 - a password for argument 2
#
WaitForDeploymentToBeDone() {
  local deploymentResultId="$1"
  local userName="$2"
  local password="$3"
  
  local deploymentState="UNKNOWN"
  
  echo "Waiting for deployment $deploymentResultId to finish..." >&2
  
  # wait 5 seconds and send a get-request to check if the plan is still running
  local response
  while [ "$deploymentState" = "UNKNOWN" ]; do
    response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/result/$deploymentResultId)
    deploymentState=${response#*\"deploymentState\":\"}
    deploymentState=${deploymentState%%\"*}
    sleep 5
  done
  
  # check if the deployment finished successfully
  echo "Bamboo Deployment $deploymentResultId finished with state '$deploymentState'!" >&2
  if [ "$deploymentState" != "SUCCESS" ]; then
    exit 1
  fi
}


# Creates a plan branch for an existing git branch.
#  Arguments:
#  1 - the identifier of the plan
#  2 - the string identifier of the git branch
#  3 - a Bamboo user name that has the necessary permissions for this operation
#  4 - a password for argument 3
#
CreatePlanBranch() {
  local planLabel="$1"
  local branch="$2"
  local userName="$3"
  local password="$4"
  
  echo "$(curl -sX PUT -u "$userName:$password" "https://ci.gerdi-project.de/rest/api/latest/plan/$planLabel/branch/$branch?vcsBranch=$branch")" >&2
}


# Deletes a Bamboo global variable.
#  Arguments:
#  1 - the name of the global variable
#  2 - the name of a Bamboo admin user
#  3 - the password the Bamboo user
#
DeleteGlobalVariable() {
  local globalVarName="$1"
  local userName="$2"
  local password="$3"
  
  local globalVariableId
  globalVariableId=$(curl -sX GET -u "$userName:$password" "https://ci.gerdi-project.de/rest/admin/latest/globalVariables" \
                     | grep -oP '(?<="id":)\d+(?=,"name":"'"$globalVarName"'")')
  
  if [ -n "$globalVariableId" ]; then
    # if the global variable exists, change its value
    curl -sX DELETE -u "$userName:$password" "https://ci.gerdi-project.de/rest/admin/latest/globalVariables/$globalVariableId"
  fi
}


# Changes the value of a Bamboo global variable. If the variable does not exist, it is created.
#  Arguments:
#  1 - the name of the global variable
#  2 - the new value of the global variable
#  3 - the name of a Bamboo admin user
#  4 - the password the Bamboo user
#
SetGlobalVariable() {
  local globalVarName="$1"
  local globalVarValue="$2"
  local userName="$3"
  local password="$4"
  
  local globalVariableId
  globalVariableId=$(curl -sX GET -u "$userName:$password" "https://ci.gerdi-project.de/rest/admin/latest/globalVariables" \
                     | grep -oP '(?<="id":)\d+(?=,"name":"'"$globalVarName"'")')
  
  if [ -n "$globalVariableId" ]; then
    # if the global variable exists, change its value
    curl -sX PUT -u "$userName:$password" -H "Content-Type: application/json" -d '{
	          "value":"'"$globalVarValue"'"
            }' "https://ci.gerdi-project.de/rest/admin/latest/globalVariables/$globalVariableId"
  else
    # if the global variable does not exist, create it
    curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
              "name":"'"$globalVarName"'",
	            "value":"'"$globalVarValue"'"
            }' "https://ci.gerdi-project.de/rest/admin/latest/globalVariables"
  fi
}


# Retrieves the name of the current deployment environment, and
# finds the corresponding branch name according to the branching model.
#
# Arguments: -
#
GetDeployEnvironmentBranch() {
 local environment="$bamboo_deploy_environment"
 
 if [ -z "$environment" ]; then
   echo "The function GetDeployEnvironmentBranch() can only be called from deployment jobs!" >&2
 fi
 
 if [ "$environment" = "Test" ]; then
   echo "master"
   
 elif [ "$environment" = "Stage" ]; then
   echo "stage"
   
 elif [ "$environment" = "Production" ]; then
   echo "production"
   
 else
   echo "Cannot convernt deployment environment '$environment' to a branch name!" >&2
   exit 1
 fi
}


# Fails with exit code 1 if the Bamboo user is not logged in.
#
ExitIfNotLoggedIn() {
  if [ -z "$bamboo_ManualBuildTriggerReason_userName" ]; then
    echo "You need to be logged in to run this job!" >&2
	exit 1
  fi
}


# Fails with exit code 1 if a specified plan variable is missing or empty.
#  Arguments:
#  1 - the name of the plan variable as it appears in the Bamboo front-end
#
ExitIfPlanVariableIsMissing() {
  local frontEndVarName="$1"
  
  local internalVarName
  internalVarName="bamboo_$frontEndVarName"
  
  local internalVarValue
  internalVarValue="${!internalVarName}"

  if [ -z "$internalVarValue" ]; then
    echo "You need to run the plan customized and overwrite the '$frontEndVarName' plan variable!" >&2
	exit 1
  fi
}
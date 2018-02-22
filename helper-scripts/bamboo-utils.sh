#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.


ExitIfNotLoggedIn() {
  if [ "$bamboo_ManualBuildTriggerReason_userName" = "" ]; then
    echo "You need to be logged in to run this job!" >&2
	exit 1
  fi
}


ExitIfPlanVariableIsMissing() {
  frontEndVarName="$1"
  internalVarName="bamboo_$frontEndVarName"
  internalVarValue="${!internalVarName}"

  if [ "$internalVarValue" = "" ]; then
    echo "You need to run the plan customized and overwrite the '$frontEndVarName' plan variable!" >&2
	exit 1
  fi
}


GetValueOfPlanVariable() {
  internalVarName="bamboo_$1"
  echo "${!internalVarName}"
}


GetBambooUserName() {
  echo "$bamboo_ManualBuildTriggerReason_userName"
}


# FUNCTION FOR RETRIEVING THE NUMBER SUFFIX THAT REPRESENTS THE PLAN BRANCH OF THE CURRENT BRANCH
GetPlanBranchId() {
  planLabel="$1"
  branch="$2"
  userName="$3"
  password="$4"
  
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/plan/$planLabel/branch/$branch)
  planBranchId=${response#*key=\"$planLabel}
  planBranchId=${planBranchId%%\"*}
  
  echo "$planBranchId"
}


# FUNCTION THAT RETRIEVES THE ID OF THE DEPLOYMENT JOB THAT IS LINKED TO A SPECIFIED BRANCH
GetDeploymentId() {
  planLabel="$1"
  userName="$2"
  password="$3"
  
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/project/all)
  deploymentId=${response%\"planKey\":\{\"key\":\"$planLabel\"\}*}

  if [ ${#deploymentId} -eq ${#response} ]; then
    echo "The plan $planLabel does not have a deployment job" >&2
    echo ""
  else  
    deploymentId=${deploymentId##*\{\"id\":}
    deploymentId=${deploymentId%%,*}
    echo "$deploymentId"
  fi
}


# FUNCTION THAT RETURNS THE PLAN_RESULT_KEY OF THE LATEST BUILD OF A BAMBOO PLAN
GetLatestBambooPlanResultKey() {
  planLabel="$1"
  planBranchId="$2"
  userName="$3"
  password="$4"
  
  # check latest finished build
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json"  https://ci.gerdi-project.de/rest/api/latest/result/$planLabel$planBranchId?max-results=1)
  planResultKey=$(echo "$response" | grep -oP '(?<=<buildResultKey>).+(?=</buildResultKey>)')
  
  # check if a build is in progress
  if [ "$planResultKey" != "" ]; then
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


# FUNCTION FOR RETRIEVING THE ID OF THE "MAVEN DEPLOY" ENVIRONMENT OF A SPECIFIED DEPLOYMENT JOB
GetMavenDeployEnvironmentId() {
  deploymentId="$1"
  userName="$2"
  password="$3"
  
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/project/$deploymentId)
  response=${bambooGetResponse#*\"environments\":\[}
  environmentId=$(echo "$response" | grep -oP "(?<=\{\"id\":)\d+(?=,.*?\"name\":\"Maven Deploy\")")
  
  if [ "$environmentId" = "" ]; then
    echo "Could not find a 'Maven Deploy' environment for deployment project $deploymentId!" >&2
  fi
  echo "$environmentId"
}


# FUNCTION THAT STARTS A BAMBOO PLAN
StartBambooPlan() {
  planLabel="$1"
  userName="$2"
  password="$3"
  
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{}' https://ci.gerdi-project.de/rest/api/latest/queue/$planLabel?stage\&executeAllStages)
  buildNumber=$(echo "$response" | grep -oP '(?<=buildNumber=")\d+(?=")')
  
  # return plan result key
  if [ "$buildNumber" = "" ]; then
    echo "Could not start Bamboo Plan $planLabel: $response" >&2
    echo ""
  else
    echo "$planLabel-$buildNumber"
  fi
}


# FUNCTION THAT WAITS FOR A BAMBOO PLAN TO FINISH
WaitForPlanToBeDone() {
  planResultKey="$1"
  userName="$2"
  password="$3"
  
  finishedResponse="{\"message\":\"Result $planResultKey not building.\",\"status-code\":404}"
  response=""
  
  echo "Waiting for plan $planResultKey to finish..." >&2
  
  # wait 3 seconds and send a get-request to check if the plan is still running
  while [ ''"$response"'' != ''"$finishedResponse"'' ]; do
    response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/result/status/$planResultKey)
    sleep 3
  done
  
  # there is a small transition period during which the build state is unknown, though the job is finished:
  buildState="Unknown"
  while [ "$buildState" = "Unknown" ]; do
    response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/result/$planResultKey)
	buildState=$(echo "$response" | grep -oP "(?<=\<buildState\>)\w+?(?=\</buildState\>)")
    sleep 3
  done
    
  # check if the plan finished successfully
  echo "Bamboo Plan $planResultKey finished with state '$buildState'!" >&2
  if [ "$buildState" != "Successful" ]; then
    exit 1
  fi
}


# FUNCTION THAT DEPLOYS A BAMBOO PROJECT
StartBambooDeployment() {
  deploymentId="$1"
  environmentId="$2"
  deploymentVersion="$3"
  planResultKey="$4"
  userName="$5"
  password="$6"
  
  requestSuffix=""
  versionId=""
  tries=1
  
  # build a version. if it already exists, append _(1)
  while [ "$versionId" = "" ]; do  
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
  deploymentResultId=$(echo "$response" | grep -oP '(?<="deploymentResultId":)\d+(?=,)')
  
  # return plan result key
  if [ "$deploymentResultId" = "" ]; then
    echo "Could not start Bamboo Plan $planLabel: $response" >&2
  fi
  echo "$deploymentResultId"
}


# FUNCTION THAT WAITS FOR A BAMBOO DEPLOYMENT TO FINISH
WaitForDeploymentToBeDone() {
  deploymentResultId="$1"
  userName="$2"
  password="$3"
  
  deploymentState="UNKNOWN"
  
  echo "Waiting for deployment $deploymentResultId to finish..." >&2
  
  # wait 5 seconds and send a get-request to check if the plan is still running
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
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

# This script offers helper functions that concern Kubernetes.



# Retrieves the type of the SCS.
#
# Arguments:
#  1 - a git clone link of the repository of which the service type is retrieved
#      (default: the first repository of the bamboo plan)
#
GetServiceType() {
  local gitCloneLink="${1-$bamboo_planRepository_1_repositoryUrl}"
  
  local projectId
  projectId=${gitCloneLink%/*}
  projectId=${projectId##*/}
  
  local projectName
  projectName=$(curl -nsX GET https://code.gerdi-project.de/rest/api/latest/projects/$projectId/ \
       | grep -oP "(?<=\"name\":\")[^\"]+" \
       | tr '[:upper:]' '[:lower:]')
     
  local serviceType
  if [ "$projectName" = "harvester" ]; then
    serviceType="harvest"
	
  elif [ "$projectName" = "frontend" ]; then
	serviceType="frontend"
	
  else
    echo "Cannot create YAML file for repositories of project $projectName ($projectId)! You have to adapt the create-k8s-yaml.sh in order to support these projects!">&2
    exit 1
  fi
  
  echo "$serviceType"
}


# Assembles the name of the service to be deployed.
#
# Arguments:
#  1 - a git clone link of the repository of which the service name is retrieved
#      (default: the first repository of the bamboo plan)
#
GetServiceName() {
  local gitCloneLink="${1-$bamboo_planRepository_1_repositoryUrl}"
  
  local projectId
  projectId=${gitCloneLink%/*}
  projectId=${projectId##*/}
  
  local repositorySlug
  repositorySlug=${gitCloneLink%.git}
  repositorySlug=${repositorySlug##*/}
  
  local projectName
  projectName=$(curl -nsX GET https://code.gerdi-project.de/rest/api/latest/projects/$projectId/ \
       | grep -oP "(?<=\"name\":\")[^\"]+" \
       | tr '[:upper:]' '[:lower:]')
	   
  echo "$repositorySlug-$projectName"
}


# Get the path to the manifest file for a specified git repository.
#
# Arguments:
#  1 - a git clone link of the repository of which the service name is retrieved
#      (default: the first repository of the bamboo plan)
#
GetManifestPath() {
  local gitCloneLink="${1-$bamboo_planRepository_1_repositoryUrl}"
  
  local repositorySlug
  repositorySlug=${gitCloneLink%.git}
  repositorySlug=${repositorySlug##*/}

  local serviceType
  serviceType=$(GetServiceType "$gitCloneLink")
  
  echo "$serviceType/$repositorySlug.yml"
}


# Generates a report of occurences of each clusterIP that is found
# in YAML files of a specified folder and sub-folders.
#
# Arguments:
#  1 - the root directory in which YAML files are being searched (default: current directory)
#
# Exit: 0, if there are duplicate clusterIDs
#
CheckDuplicateClusterIps() {
  local serviceFolder="${1-.}"
  
  local ipList
  ipList=$(GetClusterIpList "$serviceFolder")
  
  local hasDuplicates=1
  
  local clusterIp
  local occurences
  while [ -n "$ipList" ]; do
    clusterIp="$(echo "$ipList" | head -1)"
    occurences=$(echo "$ipList" | grep -c "$clusterIp")
    if [ "$occurences" -gt 1 ]; then
      hasDuplicates=0
	  printf "%-15s occurs $occurences times\n" "$clusterIp" >&2
    else
	  printf "%-15s occurs once\n" "$clusterIp" >&2
	fi
	ipList=$(echo "$ipList" | grep -v "^$clusterIp\$")
  done
  
  exit $hasDuplicates
}


# Searches for an available clusterIp in a specified range by recursively
# searching clusterIPs of YAML files within a specified folder.
#
# Arguments:
#  1 - the root directory in which YAML files are being searched
#  2 - the first three IP segments (e.g. "192.168.0.")
#  3 - the lowest viable fourth IP segment (default: 0)
#  4 - the highest viable fourth IP segment (default: 255)
#
# Return:
#  a free clusterIP within the specified range
#
GetFreeClusterIp() {
  local serviceFolder="$1"
  local ipPrefix="$2"
  local rangeFrom="${3-0}"
  local rangeTo="${4-255}"
  
  local ipList
  ipList=$(GetClusterIpList "$serviceFolder")
  
  local clusterIp
  for ((lastSegment=$rangeFrom;lastSegment <= $rangeTo;lastSegment++))
  do
    clusterIp="$ipPrefix$lastSegment"
	
	# check if clusterIP is not within the list of assigned IPs
	if ! $(echo "$ipList" | grep -q "^$clusterIp\$") ; then
      echo "$clusterIp"
	  exit 0
    fi
  done
  
  exit 1
}


# Recursively searches for clusterIPs that are defined in YAML files of a
# specified folder.
#
# Arguments:
#  1 - the root directory in which YAML files are being searched (default: current directory)
#
# Return:
#  a space-separated list of clusterIPs
#
GetClusterIpList() {
  local serviceFolder="${1-.}"
  grep -rhoP "(?<=clusterIP:\s)[0-9.]+" "$serviceFolder"
}


# Undeploys a service using a specified YAML and waits for until the service is no longer running.
#
# Arguments:
#  1 - the path to the service manifest file
#
UndeployServiceByManifest() {
  local kubernetesYaml="$1"
  
  echo "Deleting old deployment for $kubernetesYaml" >&2
  kubectl delete --ignore-not-found -f "$kubernetesYaml"
  
  until $(! kubectl get -f "$kubernetesYaml"); do
    sleep 3
  done
}
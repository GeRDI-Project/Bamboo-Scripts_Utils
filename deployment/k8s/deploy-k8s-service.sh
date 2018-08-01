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

# This script is called by Bamboo Deployment Jobs.
# It deploys a service defined by a YAML file to the Kubernetes cluster.
# The prerequisite for this script to work is that the create-k8s-yaml script was executed
# before the execution of this script.
#
# Arguments: -
#
# Bamboo Plan Variables: -


# treat unset variables as an error when substituting
set -u

# define global variables
KUBERNETES_YAML_DIR="gerdireleases"

# load helper scripts
source ./scripts/helper-scripts/k8s-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# Deploys the service to the Kubernetes cluster.
# If the service was running before, it is shut down.
#
# Arguments:
#  1 - the path to the service manifest file
#
DeployK8sService()
{
  local kubernetesYaml="$1"
  
  echo "Deleting old deployment for $kubernetesYaml" >&2
  kubectl delete --ignore-not-found -f "$kubernetesYaml"
  
  echo "Waiting for old deployment $update to terminate" >&2
  WaitForDeletion "$kubernetesYaml"
  
  echo "Creating new deployment for $kubernetesYaml" >&2
  kubectl apply -f "$kubernetesYaml"
}


# Waits for until a service is no longer running.
#
# Arguments:
#  1 - the path to the service manifest file
#
WaitForDeletion() {
  local kubernetesYaml="$1"
  
  until $(! kubectl get -f "$kubernetesYaml"); do
    sleep 3
  done
}


# The main function to be executed in this script.
#
Main() {  
  local gitCloneLink="$bamboo_planRepository_1_repositoryUrl"
  
  local kubernetesYaml
  kubernetesYaml="$KUBERNETES_YAML_DIR/$(GetManifestPath "$gitCloneLink")"
  
  DeployK8sService "$kubernetesYaml"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"

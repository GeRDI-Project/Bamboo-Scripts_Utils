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
# Bamboo Plan Variables:
#  bamboo_planRepository_1_repositoryUrl 
#    The ssh clone link to the first repository of the plan.


# treat unset variables as an error when substituting
set -u

# define global variables
KUBERNETES_YAML_DIR="gerdireleases"

# load helper scripts
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/k8s-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# The main function to be executed in this script.
#
Main() {  
  local gitCloneLink="$bamboo_planRepository_1_repositoryUrl"
  
  local kubernetesYaml
  kubernetesYaml="$KUBERNETES_YAML_DIR/$(GetManifestPath "$gitCloneLink")"
  
  local environment
  environment=$(GetDeployEnvironmentName)
  
  if [ "$environment" = "" ]; then
    echo "Could not deploy $kubernetesYaml: No environment defined for deploy environment $bamboo_deploy_environment!" >&2
	exit 1
  fi
	
  echo "Creating new deployment for $kubernetesYaml on the $environment environment." >&2
  
  if [ "$environment" = "test" ]; then
    kubectl apply -f "$kubernetesYaml"
  
  else
    kubectl apply -f "$kubernetesYaml" --context=$environment
  fi
  
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"

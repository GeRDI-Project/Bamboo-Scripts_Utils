#!/bin/bash

# Copyright © 2018 Tobias Weber  (http://www.gerdi-project.de/)
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

# treat unset variables as an error when substituting
set -u


#########################
#  FUNCTION DEFINITIONS #
######################### 

log() {
    echo $(date) $1
}

waitForIt() {
    until kubectl get po | grep -q "Terminating"
    do
        sleep 3
        log $(kubectl get po | grep "Terminating")
    done
}

# The main method of this script.
#
Main() {
  for update in `git log -1 --name-status | egrep '^M' | awk '{ print $2 }'`
  do
      log "Deleting old deployment for $update"
      kubectl delete -f $update 
      log "Waiting for old deployment $update to terminate"
      waitForIt $update
      log "Creating new deployment for $update"
      kubectl apply -f $update
  done
  
  for new in `git log -1 --name-status | egrep '^C' | awk '{ print $2 }'`
  do
      kubectl apply -f $new
  done

  for new in `git log -1 --name-status | egrep '^D' | awk '{ print $2 }'`
  do
      kubectl delete -f $new
  done
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"

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

# This script searches for non-executable shell scripts in a specified directory
# and fails with a detailed error message if it finds any.
#
# Arguments:
#  1 - the folder in which shell scripts are to be searched
#
# Bamboo Plan Variables: -
#

# treat unset variables as an error when substituting
set -u


#########################
#  FUNCTION DEFINITIONS #
#########################

Main() {
  local searchFolder="${1-}"
  
  if [ -z "$searchFolder" ]; then
    echo "Missing argument 1: You need to specify a folder where you want to search for shell scripts!" >&2
    exit 1
  fi
  
  echo "Testing if shell scripts are executable..." >&2
  
  local allScripts
  allScripts=$(find "$searchFolder" -name "*.sh")
  
  local badScripts=""
  
  while read scriptPath; do
    if [ ! -x "$scriptPath" ]; then
      badScripts="$badScripts$scriptPath\n"
    fi
  done <<< $(echo -e "$allScripts")
  
  if [ -n "$badScripts" ]; then
    echo -e "FAILED: The following shell scripts are lacking their execution flag:\n$badScripts" >&2
    exit 1
  fi
  echo "SUCCESS!" >&2
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
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

# This script offers helper functions that concern GeRDI's Atlassian tools in general.
 
 
# Retrieves the email address of a GeRDI user.
#  Arguments:
#  1 - an Atlassian user name of a user that is allowed to view user profiles
#  2 - the login password that belongs to argument 1
#  3 - the Atlassian user name of the user of which the email address is to be retrieved (optional)
#
GetAtlassianUserEmailAddress() {
  local userName="$1"
  local password="$2"
  local checkedUserName="${3-$1}"
  
  local userProfile
  userProfile=$(curl -sX GET -u "$userName:$password" https://tasks.gerdi-project.de/rest/api/2/user?username="$checkedUserName")
  echo "$userProfile" | grep -oP "(?<=\"emailAddress\":\")[^\"]+"
}


# Retrieves the display name (usually a person's full name) of a GeRDI user.
#  Arguments:
#  1 - an Atlassian user name of a user that is allowed to view user profiles
#  2 - the login password that belongs to argument 1
#  3 - the Atlassian user name of the user of which the display name is to be retrieved (optional)
#
GetAtlassianUserDisplayName() {
  local userName="$1"
  local password="$2"
  local checkedUserName="${3-$1}"
  
  local userProfile
  userProfile=$(curl -sX GET -u "$userName:$password" https://tasks.gerdi-project.de/rest/api/2/user?username="$checkedUserName")
  echo "$userProfile" | grep -oP "(?<=\"displayName\":\")[^\"]+"
}


# This function fails with exit code 1, if provided Atlassian login credentials are incorrect.
#  Arguments:
#  1 - an Atlassian user name
#  2 - the login password that belongs to argument 1
#
ExitIfAtlassianCredentialsWrong() {
  local userName="$1"
  local password="$2"
  
  $(curl -sfX HEAD -u "$userName:$password" "https://code.gerdi-project.de/rest/api/latest/projects/")
  if [ $? -ne 0 ]; then
    echo "Incorrect Atlassian credentials!" >&2
    exit 1
  fi
}
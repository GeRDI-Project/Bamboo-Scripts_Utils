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


# Retrieves the elements of the 'values' JSON array of a paginated Atlassian REST API request.
# If the request is split up to multiple pages, all elements of all 'values' arrays are concatenated
# to a single comma-separated list.
#  Arguments:
#  1 - an Atlassian REST API URL
#  2 - the pagination start index (optional, default: 0)
#  3 - an Atlassian user name (optional)
#  4 - the password for the Atlassian user name (optional)
GetJoinedAtlassianResponse() {
  local url="$1"
  local startIndex="${2-0}"
  local userName="${3-}"
  local password="${4-}"
  
  local joinedValues
  JoinValuesArray() {
    if [ -n "$joinedValues" ]; then
      joinedValues="$joinedValues,$1"
    else
      joinedValues="$1"
    fi    
  }
  
  ProcessJoinedAtlassianResponse "$url" "JoinValuesArray" "" "$startIndex" "$userName" "$password" >&2
  echo "$joinedValues"
}


# Retrieves and processes the elements of the 'values' JSON array of a paginated Atlassian REST API request.
# If the request is split up to multiple pages, the 'values'-elements of each page response are processed
# using a specified function.
#  Arguments:
#  1 - an Atlassian REST API URL
#  2 - the name of a function that receives the 'values' array content as the first argument
#  3 - additional arguments that are passed to the function
#  4 - the pagination start index (optional, default: 0)
#  5 - an Atlassian user name (optional)
#  6 - the password for the Atlassian user name (optional)
ProcessJoinedAtlassianResponse() {
  local url="$1"
  local functionName="$2"
  local functionArguments="${3-}"
  local startIndex="${4-0}"
  local userName="${5-}"
  local password="${6-}"
  
  # Atlassian uses a non-consistent page API, redundant query parameters mitigate that issue
  local startQuery
  if $(echo "$url" | grep -q '?'); then
    startQuery="&start=$startIndex&startAt=$startIndex"
  else
    startQuery="?start=$startIndex&startAt=$startIndex"
  fi
  
  local response
  if [ -n "$userName" ]; then
    response=$(curl -sX GET -u "$userName:$password" "$url$startQuery")
  else
    response=$(curl -nsX GET "$url$startQuery")
  fi
  
  # retrieve pagination metadata
  local metadata
  metadata="${response%%,\"values\":[*}"
  metadata="$metadata${response##*]}"
  
  # retrieve values array
  response=${response#*\"values\":[}
  response=${response%]*}
  response=$(echo "$response" | sed 's~'"'"'~\\'"'"'~g')

  # check if this is the last page of a multi-page-request
  local isLast
  isLast=$(echo "$metadata" | grep -oP '(?<="isLast":|"isLastPage":)[a-z]+')
  
  # process response
  eval "'$functionName'" "$'$response' $functionArguments"
  
  if ! $isLast; then
    # calculate the next start index of a multi-page request
    local resultsPerPage
    resultsPerPage=$(echo "$metadata" | grep -oP '(?<="limit":|"maxResults":|"max-results":)[0-9]+')
    local nextStart
    nextStart=$(expr $startIndex + $resultsPerPage)
  
    ProcessJoinedAtlassianResponse "$1" "$2" "$3" "$nextStart" "$5" "$6"
  fi
}


# This function fails with exit code 1, if provided Atlassian login credentials are incorrect.
#  Arguments:
#  1 - an Atlassian user name
#  2 - the login password that belongs to argument 1
#
ExitIfAtlassianCredentialsWrong() {
  local userName="$1"
  local password="$2"
  
  curl -sfX HEAD -u "$userName:$password" "https://code.gerdi-project.de/rest/api/latest/projects/" >&2
  if [ $? -ne 0 ]; then
    echo "Incorrect Atlassian credentials!" >&2
    exit 1
  fi
}
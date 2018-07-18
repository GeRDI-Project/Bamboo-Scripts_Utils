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

# This script offers helper functions that concern the GeRDI JIRA.


# Sets a JIRA ticket from "Selected for Development" to "In Progress".
#  Arguments:
#  1 - the JIRA ticket id of the ticket that is to be started
#  2 - a JIRA user name
#  3 - a password for argument 2
#
StartJiraTask() {
  local taskKey="$1"
  local userName="$2"
  local password="$3"
  
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 111}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
  
  echo "Setting $taskKey to 'In Progress'" >&2
  
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 81}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
  
}


# Sets a JIRA ticket from "In Progress" to "In Review".
#  Arguments:
#  1 - the JIRA ticket id of the ticket that is to be reviewed
#  2 - a JIRA user name
#  3 - a password for argument 2
#
ReviewJiraTask() {
  local taskKey="$1"
  local userName="$2"
  local password="$3"
  
  # set to Review
  echo "Setting $taskKey to 'In Review'" >&2
  
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 101}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# Sets a JIRA ticket from "In Review" to "Done".
#  Arguments:
#  1 - the JIRA ticket id of the ticket that is to be started
#  2 - a JIRA user name
#  3 - a password for argument 2
#
FinishJiraTask() {
  local taskKey="$1"
  local userName="$2"
  local password="$3"
  
  echo "Setting $taskKey to 'Done'" >&2
  
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 71}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# Sets a JIRA ticket from "In Progress" to "Will not fix" .
#  Arguments:
#  1 - the JIRA ticket id of the ticket that is to be started
#  2 - a message that will be posted as a comment to the JIRA ticket
#  3 - a JIRA user name
#  4 - a password for argument 3
#
AbortJiraTask() {
  local taskKey="$1"
  local reason="$2"
  local userName="$3"
  local password="$4"
  
  # set to WNF
  echo "Setting $taskKey to 'Will not Fix'" >&2
  
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 181},
  "update": {
        "comment": [{"add": {"body": "'"$reason"'"}}]
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# Creates a JIRA ticket in the System Architecture and Integration project.
#  Arguments:
#  1 - the title of the JIRA ticket
#  2 - the description of the JIRA ticket
#  3 - a JIRA user name
#  4 - a password for argument 3
#
CreateJiraTicket() {
  local title="$1"
  local description="$2"
  local userName="$3"
  local password="$4"
  
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "fields": {
      "summary": "'"$title"'",
      "description": "_This ticket was created by a Bamboo job._\n\n'"$description"'",
      "issuetype": { "id": "10002"},
      "project": {"id": "10400"},
      "customfield_10006": 0
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue)
  
  local jiraKey
  jiraKey=${response#*\"key\":\"}
  jiraKey=${jiraKey%%\"*}
  
  echo "Created JIRA task $jiraKey" >&2
  
  echo "$jiraKey"
}


# Creates a sub-task in a JIRA ticket of the System Architecture and Integration project.
#  Arguments:
#  1 - the identifier of the JIRA ticket for which the sub-task is created
#  2 - the title of the sub-task
#  3 - the description of the sub-task
#  4 - a JIRA user name
#  5 - a password for argument 4
#
CreateJiraSubTask() {
  local jiraParentKey="$1"
  local title="$2"
  local description="$3"
  local userName="$4"
  local password="$5"
  
  local response
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "fields": {
      "summary": "'"$title"'",
    "description": "'"$description"'",
    "issuetype": { "id": "10003"},
    "project": {"id": "10400"},
    "parent": {"key": "'"$jiraParentKey"'"}
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue)
  
  local subTaskKey
  subTaskKey=${response#*\"key\":\"}
  subTaskKey=${subTaskKey%%\"*}
  
  echo "Added JIRA sub-task $subTaskKey to issue $jiraParentKey" >&2
  
  echo "$subTaskKey"
}


# Adds a JIRA ticket to the ongoing Sprint of the System Architecture and Integration project.
#  Arguments:
#  1 - the identifier of the JIRA ticket which is to be added
#  2 - a JIRA user name
#  3 - a password for argument 3
#
AddJiraTicketToCurrentSprint() {
  local jiraKeyToAdd="$1"
  local userName="$2"
  local password="$3"
    
  # retrieve active sprint name
  local response
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://tasks.gerdi-project.de/rest/agile/latest/board/25/sprint) 

  local sprintId  
  sprintId=${response##*\"id\":}
  sprintId=${sprintId%%,*}
   
  # add issue to sprint
  curl --output '/dev/null' -sX PUT -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "idOrKeys":["'"$jiraKeyToAdd"'"],
    "customFieldId":10005,
    "sprintId":'"$sprintId"',
    "addToBacklog":false
  }' https://tasks.gerdi-project.de/rest/greenhopper/1.0/sprint/rank
  
  echo "Added $jiraKeyToAdd to Sprint $sprintId" >&2
}
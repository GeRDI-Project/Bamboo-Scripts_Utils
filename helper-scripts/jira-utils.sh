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

# This script offers helper functions that concern the GeRDI JIRA.

# FUNCTION FOR STARTING A JIRA ISSUE
StartJiraTask() {
  taskKey="$1"
  userName="$2"
  password="$3"
  
  #echo "Setting $taskKey to 'Selected for Development'" >&2
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 111}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
  
  echo "Setting $taskKey to 'In Progress'" >&2
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 81}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
  
}


# FUNCTION FOR SETTING A JIRA ISSUE TO REVIEW
ReviewJiraTask() {
  taskKey="$1"
  userName="$2"
  password="$3"
  
  # set to Review
  echo "Setting $taskKey to 'In Review'" >&2
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 101}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR SETTING A JIRA ISSUE TO DONE
FinishJiraTask() {
  taskKey="$1"
  userName="$2"
  password="$3"
  
  echo "Setting $taskKey to 'Done'" >&2
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 71}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR ABORTING A JIRA ISSUE IN PROGRESS
AbortJiraTask() {
  taskKey="$1"
  reason="$2"
  userName="$3"
  password="$4"
  
  # set to WNF
  echo "Setting $taskKey to 'Will not Fix'" >&2
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "transition": {"id": 181},
  "update": {
        "comment": [{"add": {"body": "'"$reason"'"}}]
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR CREATING A JIRA TICKET
CreateJiraTicket() {
  title="$1"
  description="$2"
  userName="$3"
  password="$4"
  
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "fields": {
      "summary": "'"$title"'",
      "description": "_This ticket was created by a Bamboo job._\n\n'"$description"'",
      "issuetype": { "id": "10002"},
      "project": {"id": "10400"},
      "customfield_10006": 0
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue)
  
  jiraKey=${response#*\"key\":\"}
  jiraKey=${jiraKey%%\"*}
  
  echo "Created JIRA task $jiraKey" >&2
  
  echo "$jiraKey"
}


# FUNCTION FOR CREATING A JIRA SUB-TASK
CreateJiraSubTask() {
  jiraParentKey="$1"
  title="$2"
  description="$3"
  userName="$4"
  password="$5"
  
  response=$(curl -sX POST -u "$userName:$password" -H "Content-Type: application/json" -d '{
    "fields": {
      "summary": "'"$title"'",
    "description": "'"$description"'",
    "issuetype": { "id": "10003"},
    "project": {"id": "10400"},
    "parent": {"key": "'"$jiraParentKey"'"}
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue)
  
  subTaskKey=${response#*\"key\":\"}
  subTaskKey=${subTaskKey%%\"*}
  
  echo "Added JIRA sub-task $subTaskKey to issue $jiraParentKey" >&2
  
  echo "$subTaskKey"
}

# FUNCTION FOR ADDING AN ISSUE TO THE CURRENT SPRINT
AddJiraTicketToCurrentSprint() {
  jiraKeyToAdd="$1"
  userName="$4"
  password="$5"
    
  # retrieve active sprint name
  response=$(curl -sX GET -u "$userName:$password" -H "Content-Type: application/json" https://tasks.gerdi-project.de/rest/agile/latest/board/25/sprint)    
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
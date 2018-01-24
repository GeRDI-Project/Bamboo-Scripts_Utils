# check login
authorEmail="$bamboo_ManualBuildTriggerReason_userName"
if [ "$authorEmail" = "" ]; then
echo "Please log in to Bamboo!"
exit 1
fi

# check if password exists
userPw="$bamboo_passwordGit"
if [ "$userPw" = "" ]; then
echo "You need to specify your BitBucket password by setting the 'passwordGit' variable when running the plan customized!"
exit 1
fi

# check if all required variables exist
if [ "$bamboo_providerName" = "" ] \
|| [ "$bamboo_providerUrl" = "" ] \
|| [ "$bamboo_authorOrganization" = "" ] \
|| [ "$bamboo_authorOrganizationUrl" = "" ]
then
echo "Some Variables are missing! Make sure to fill out all variables and to run the plan customized!"
exit 1
fi

# create repository
response=$(curl -sX POST -u "$authorEmail:$userPw" -H "Content-Type: application/json" -d '{
    "name": "'"$bamboo_providerName"'",
    "scmId": "git",
    "forkable": true
}' https://code.gerdi-project.de/rest/api/1.0/projects/HAR/repos/)

# check for BitBucket errors
errorsPrefix="\{\"errors\""
if [ "${response%$errorsPrefix*}" = "" ]
then
echo "Could not create repository for the Harvester:"
echo "$response"
exit 1
fi

# retrieve the urlencoded repository name from the curl response
encodedRepositoryName="$response"
encodedRepositoryName=${encodedRepositoryName#*\{\"slug\":\"}
encodedRepositoryName=${encodedRepositoryName%%\"*}

echo "Created repository '$encodedRepositoryName'."

# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder"
rm -fr harvesterSetupTemp
mkdir harvesterSetupTemp
cd harvesterSetupTemp

# clone newly created repository
encodedEmail=$(echo "$authorEmail" | sed -e "s/@/%40/g")
echo "Cloning repository https://$encodedEmail@code.gerdi-project.de/scm/har/$encodedRepositoryName.git"
#echo "PW: $userPw"
cloneResponse=$(git clone -q "https://$encodedEmail:$userPw@code.gerdi-project.de/scm/har/$encodedRepositoryName.git")
returnCode=$?
if [ $returnCode -ne 0 ]; then
 echo "Could not clone GIT repository!"
 exit 1
fi
cd $encodedRepositoryName


# Get Author Full Name
authorFullName=$(curl -sX GET -u $authorEmail:$userPw https://ci.gerdi-project.de/browse/user/$encodedEmail)
authorFullName=${authorFullName#*<title>}
authorFullName=${authorFullName%%:*}


# define function for retrieving the latest version of a gerdi maven project
GetGerdiMavenVersion () {
  metaData=$(curl -sX GET https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$1/maven-metadata.xml)
  ver=${metaData#*<latest>}
  ver=${ver%</latest>*}
  if [ "$ver" = "$metaData" ]; then
   ver=${metaData##*<version>}
   ver=${ver%</version>*}
  fi
  echo "$ver"
}

# get the latest version of the Harvester Parent Pom
harvesterSetupVersion=$(GetGerdiMavenVersion "GeRDI-harvester-setup")
echo "Latest version of the HarvesterSetup is: $harvesterSetupVersion"

# create a basic pom.xml that will fetch the harvester setup
echo "Creating temporary pom.xml"
echo "<project>" >> pom.xml
echo " <modelVersion>4.0.0</modelVersion>" >> pom.xml
echo " <parent>" >> pom.xml
echo "  <groupId>de.gerdi-project</groupId>" >> pom.xml
echo "  <artifactId>GeRDI-harvester-setup</artifactId>" >> pom.xml
echo "  <version>$harvesterSetupVersion</version>" >> pom.xml
echo " </parent>" >> pom.xml
echo " <artifactId>temporary-harvester-setup</artifactId>" >> pom.xml
echo " <repositories>" >> pom.xml
echo "  <repository>" >> pom.xml
echo "   <id>Sonatype</id>" >> pom.xml
echo "   <url>https://oss.sonatype.org/content/repositories/snapshots/</url>" >> pom.xml
echo "  </repository>" >> pom.xml
echo " </repositories>" >> pom.xml
echo "</project>" >> pom.xml

# retrieve and unpack the harvester setup files
echo "Generating harvester setup files"
response=$(mvn generate-resources -Psetup)
returnCode=$?
if [ $returnCode -ne 0 ]; then
 echo "$response"
 echo "Could not generate Maven resources!"
 exit 1
fi

# get the latest version of the Harvester Parent Pom
parentPomVersion=$(GetGerdiMavenVersion "GeRDI-parent-harvester")
echo "Latest version of the Harvester Parent Pom is: $parentPomVersion"

# rename placeholders for the unpacked files
chmod o+rw scripts/renameSetup.sh
chmod +x scripts/renameSetup.sh
./scripts/renameSetup.sh\
 "$bamboo_providerName"\
 "$bamboo_providerUrl"\
 "$authorFullName"\
 "$authorEmail"\
 "$bamboo_authorOrganization"\
 "$bamboo_authorOrganizationUrl"\
 "$parentPomVersion"
 
# check if bamboo plans already exist
providerClassName=$(ls src/main/java/de/gerdiproject/harvest/*ContextListener.java)
providerClassName=${providerClassName%ContextListener.java}
providerClassName=${providerClassName##*/}

planKey=$( echo "$providerClassName" | sed -e "s~[a-z]~~g")HAR
doPlansExist=0
  
echo "Checking Bamboo Plans"
response=$(curl -sX GET -u $authorEmail:$userPw https://ci.gerdi-project.de/browse/CA-$planKey)
cutResponse=${response%<title>Bamboo error reporting - GeRDI Bamboo</title>*}
if [ "$response" != "" ] && [ "$cutResponse" = "$response" ]; then
  doPlansExist=1
fi
if [ $doPlansExist -ne 0 ]; then
  echo "Plans with the key '$planKey' already exist!"
  
  # delete repository
  response=$(curl -sX DELETE -u $authorEmail:$userPw https://code.gerdi-project.de/rest/api/1.0/projects/HAR/repos/$encodedRepositoryName)
  exit 1
fi
 
# run AStyle without changing the files
echo "Formatting files with AStyle"
astyleResult=$(astyle --options="/usr/lib/astyle/file/kr.ini" --recursive --formatted "src/*")

# commit and push all files
echo "Adding files to GIT"
git add -A ${PWD}

echo "Committing files to GIT"
git config user.email "$authorEmail"
git config user.name "$authorFullName"
git commit -m "Bamboo: Created harvester repository for the provider '$bamboo_providerName'."

echo "Pushing files to GIT"
git push -q


echo "Creating temporary Bamboo-Specs credentials"
cd bamboo-specs
touch .credentials
echo "username=$authorEmail" >> .credentials
echo "password=$userPw" >> .credentials

echo "Running Bamboo-Specs"
mvn -Ppublish-specs

# clean up
echo "Removing the temporary directory"
cd ../../
rm -fr harvesterSetupTemp
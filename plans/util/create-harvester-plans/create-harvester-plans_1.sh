# check login
authorEmail="$bamboo_ManualBuildTriggerReason_userName"
if [ "$authorEmail" = "" ]; then
echo "Please log in to Bamboo!"
exit 1
fi
encodedEmail=$(echo "$authorEmail" | sed -e "s/@/%40/g")

# check if password exists
userPw="$bamboo_gitPassword"
if [ "$userPw" = "" ]; then
echo "You need to specify your BitBucket password by setting the 'gitPassword' variable when running the plan customized!"
exit 1
fi

repositoryUrl="$bamboo_gitCloneLink"
if [ "$repositoryUrl" = "" ]; then
echo "You need to specify a clone link of an existing harvester repository!"
exit 1
fi

overwriteFlag="$bamboo_replacePlans"

projectAbbrev=${repositoryUrl%/*}
projectAbbrev=${projectAbbrev##*/}

repositorySlug=${repositoryUrl##*/}
repositorySlug=${repositorySlug%.git}

echo "Bitbucket Project: '$projectAbbrev'"
echo "Slug: '$repositorySlug'"


# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder"
rm -fr harvesterSetupTemp
mkdir harvesterSetupTemp
cd harvesterSetupTemp


echo "Cloning repository https://$encodedEmail@code.gerdi-project.de/scm/$projectAbbrev/$repositorySlug.git"
cloneResponse=$(git clone -q https://$encodedEmail:$userPw@code.gerdi-project.de/scm/$projectAbbrev/$repositorySlug.git .)
returnCode=$?
if [ $returnCode -ne 0 ]; then
 echo "Could not clone GIT repository!"
 exit 1
fi


# get class name of the provider
providerClassName=$(ls src/main/java/de/gerdiproject/harvest/*ContextListener.java)
providerClassName=${providerClassName%ContextListener.java}
providerClassName=${providerClassName##*/}
echo "Provider Class Name: '$providerClassName'"


# check if such plans already exist and should be overridden
if [ "$overwriteFlag" != "true" ] && [ "$overwriteFlag" != "yes" ] && [ "$overwriteFlag" != "1" ]; then
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
    exit 1
  fi
else
  echo "Overriding any existing plans"
fi


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
mv pom.xml backup-pom.xml
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


# rename placeholders for the unpacked files
chmod o+rw scripts/renameSetup.sh
chmod +x scripts/renameSetup.sh
./scripts/renameSetup.sh\
 "$providerClassName"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"

# restore old pom 
mv -f backup-pom.xml pom.xml


echo "Creating temporary Bamboo-Specs credentials"
cd bamboo-specs
touch .credentials
echo "username=$authorEmail" >> .credentials
echo "password=$userPw" >> .credentials

echo "Running Bamboo-Specs"
mvn -Ppublish-specs

# clean up
echo "Removing the temporary directory"
cd ../
rm -fr harvesterSetupTemp
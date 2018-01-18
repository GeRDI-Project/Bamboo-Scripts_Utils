mvn clean test findbugs:check "-Dmaven.test.skip=true"
returnCode=$?

if [ $returnCode -ne 0 ]
then
echo "\\nOpen StaticLesson6.zip with the password 'oh-long-johnson'"
exit 1
else
echo "FindBugs found no issues!"
exit 0
fi
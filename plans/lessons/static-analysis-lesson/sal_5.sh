mvn clean pmd:check
returnCode=$?
if [ $returnCode -ne 0 ]
then
echo "\\nOpen StaticLesson5.zip with the password 'i-like-trains'"
exit 1
else
echo "PMD found no issues!"
exit 0
fi
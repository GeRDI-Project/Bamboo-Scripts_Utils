mvn clean compile
returnCode=$?
echo "RETURNCODE: $returnCode"
if [ $returnCode -ne 0 ]
then
echo "\\nOpen StaticLesson3.zip with the password 'banana-king'"
exit 1
fi
exit 0
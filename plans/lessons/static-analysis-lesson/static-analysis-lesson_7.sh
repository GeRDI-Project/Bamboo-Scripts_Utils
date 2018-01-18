mvn clean test
returnCode=$?

if [ $returnCode -ne 0 ]
then
echo "\\nUnitTests failed! Make sure the behavior remains the same when refactoring code!"
exit 1
else
echo "All UnitTests passed!"
echo "\\nOpen StaticLesson7.zip with the password 'megalovania'"
exit 0
fi
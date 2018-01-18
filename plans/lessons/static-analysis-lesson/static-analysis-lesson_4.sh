mvn clean pmd:cpd-check
returnCode=$?
if [ $returnCode -ne 0 ]
then
echo "\\nOpen StaticLesson4.zip with the password 'epic-sax-guy'"
exit 1
else
echo "Copy-Paste-Detector found no issues!"
exit 0
fi
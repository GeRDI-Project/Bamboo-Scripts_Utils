testPath="src/test/java/de/gerdiproject/StaticAnalysisTests.java"
echo "\\nChecking hash of UnitTests..."

requiredChecksum="2159138236 4762 src/test/java/de/gerdiproject/StaticAnalysisTests.java"
testChecksum=$(cksum $testPath)

if [ "$requiredChecksum" = "$testChecksum" ]
then
echo "Success!"
exit 0
else
echo "FAILED! UnitTests have been modified!\\nDO NOT MODIFY THE FILE StaticAnalysisTests.java !"
exit 1
fi
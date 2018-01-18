echo "\\nChecking code formatting:"

formattingStyle="kr"
sourcePath="src\\"
astyleLibPath="\\usr\lib\astyle\file\\"

# run AStyle without changing the files
result=$(astyle --options="$astyleLibPath$formattingStyle.ini" --dry-run --recursive --formatted $sourcePath*)

# remove all text up until the name of the first unformatted file
newResult=${result#*Formatted  }

errorCount=0

while [ "$newResult" != "$result" ]
do
errorCount=$(($errorCount + 1))
result="$newResult"

# retrieve the name of the unformatted file
fileName=$(echo $result | sed -e "s/Formatted .*//gi")
 
# log the unformatted file
echo "Unformatted File: $fileName"

# remove all text up until the name of the next unformatted file
newResult=${result#*Formatted  }
done

if [ $errorCount -ne 0 ]
then
echo "Found $errorCount unformatted files! Please use the AristicStyle formatter before committing your code!"
echo "\\nOpen StaticLesson2.zip using the password 'llamas-with-hats'"
echo "If you completed a later lesson already, you forgot to format your code before pushing it ;)"
exit 1
else
echo "All files are properly formatted!"
exit 0
fi
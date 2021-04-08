result=0

script=( ./*.lua )
for file in "${script[@]}"
do
    script_output=$(./luatos.exe $file)
    if [ $? -eq 0 ]
    then
        echo "$file pass"
    else
        echo "$file not pass"
        echo "$script_output"
        result=1
    fi
done
echo "all done, exit with $result"
exit $result

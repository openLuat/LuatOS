echo -e "\e[1;33m=====test start=====\e[0m"

result=0

script=( ./*.lua )
for file in "${script[@]}"
do
    script_output=$(./luatos.exe $file)
    if [ $? -eq 0 ]
    then
        echo -e "\e[1;32mpass:\e[0m $file"
    else
        echo -e "\e[1;31mfail:\e[0m $file"
        echo "$script_output"
        result=1
    fi
done
echo -e "\e[1;33m====all done, exit with $result====\e[0m"
exit $result

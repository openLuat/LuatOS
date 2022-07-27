echo -e "\e[1;33m===== test start =====\e[0m"

result=0

script=( ./*.lua )
for file in "${script[@]}"
do
    script_output=$(./luatos.exe $file)
    if grep -q "E/lua.err" <<< "$script_output";
    then
        echo -e "[\e[1;31mfail\e[0m] $file"
        echo "$script_output"
        result=1
    else
        echo -e "[\e[1;32mpass\e[0m] $file"
    fi
done
if [ $result -eq 0 ]
then
    echo -e "\e[1;33m==== all tests passed ====\e[0m"
else
    echo -e "\e[1;31m==== not pass ====\e[0m"
fi

exit $result

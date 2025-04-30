# Fresh upgrade build with Bahasa
sent any bug to hi@fredriclesomar.my.id

1. Shell command, first need to access grant:
> chmod +x upgrade.sh

2. Make sure, your clone this repo or create manualy from unix editor.
3. Solution, if you find some error like this: bash: ./xscript.sh: /bin/bash^M: bad interpreter: No such file or directory
> sed -i 's/\r//' xscript.sh

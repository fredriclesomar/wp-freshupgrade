# Fresh upgrade WordPress, build with Bahasa.
The fresh upgrade process of WordPress will run automatically. Please ensure that you have created a backup as a precaution. By default, your media files will remain safe. 

This tool will assist you in updating all WordPress websites with a single click, and you only need to wait until the process is completed. Sent any bug to hi@fredriclesomar.my.id

1. Shell command, first need to access grant:
> chmod +x upgrade.sh
2. Exec the shell:
> $ ./upgrade.sh -u usercPanel
2. Make sure, your clone this repo or create manualy from unix editor.
3. Solution, if you find some error like this: bash: ./upgrade.sh: /bin/bash^M: bad interpreter: No such file or directory
> sed -i 's/\r//' upgrade.sh

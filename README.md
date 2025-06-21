# Fresh upgrade WordPress, build with Bahasa.
This tool will assist you in updating all WordPress websites with a single click, and you only need to wait until the process is completed. Sent any bug to hi@fredriclesomar.my.id

Note: $ ./upgrade.sh --help

# Automated installation script:
```bash
bash <(curl -s https://raw.githubusercontent.com/fredriclesomar/wp-freshupgrade/refs/heads/master/upgrade.sh) -u usercPanel
```

# Manualy installation script:
1. Grant execution permission to the shell script by running:
> chmod +x upgrade.sh
2. Execute the script using:
> $ ./upgrade.sh -u usercPanel
2. Ensure that you have cloned this repository properly, or created the script manually using a Unix-compatible text editor.
3. If you encounter an error such as:
bash: ./upgrade.sh: /bin/bash^M: bad interpreter: No such file or directory
It likely means the file contains Windows-style line endings. You can fix it by running:
> sed -i 's/\r//' upgrade.sh

**I recommend running this script as the root user, especially if your cPanel account has limited CPU or RAM resources, and if it hosts multiple WordPress installations.


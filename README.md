An script for ubuntu 22 server setup.

make a ssh session an run:  
```
curl -o script.sh https://raw.githubusercontent.com/codetrend104/server-setup/main/script.sh
chmod +x script.sh
./script.sh -php 7.4,8.1,8.2 -u username-you-need -p password-you-want -mysql mysql-password
```
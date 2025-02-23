# Terraform-ansible-haproxy-apache
Конфигурационный файл Terraform, который создает 5 VM:
1. 1 экзмепляр для Haproxy
2. 1 экземпляр для Ansible
3. 3 эземпляра для Apache

Далее устанавливает необходимые пакеты на VM Ansible и скачивает роли для дальнейшего развертывания Haproxy и Apache. 
Ссылка на роли - https://github.com/abeikenov/ansible_roles.git 

Роли Ansible устанавливают необходимые пакеты для Haproxy и Apache, настраивают балансировку на 3 эземпляра Apache по принципу RoundRobin.

Небольшие пояснения:
1. На каждом сервере выполнябтся sed - это необходимо для скачивания пакетов, т. к. Centos 7 с 1 июля снят с поддержки
2. В ansible ролях выполняется настройка Selinux (setsebool -P httpd_can_network_connect 1), чтобы не отключать его, но иметь доступ по http порту
3. Есть небольшая задержка командой sleep 300, т. к. не все пакеты ansible успевают установиться к моменту выполнения ansible-playbook
4. При выполнении ansible-playbook отключаем проверку ANSIBLE_HOST_KEY_CHECKING=False. Т. к. хосты вновь созданные, нету риска для отключения

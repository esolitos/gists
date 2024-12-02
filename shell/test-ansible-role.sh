#!/bin/bash
#
# Test Ansile role inside container
#
# Inspired by the wonderful work of Jeff Geerling (@geerlingguy)
# https://gist.github.com/geerlingguy/73ef1e5ee45d8694570f334be385e181
# and @samdoran
# https://gist.github.com/samdoran/c3d392ee697881fa33a1d1a65814a07b
#
# Usage: [OPTIONS] ./tests/test.sh
#   - distro: a supported Docker distro version (default = "centos7")
#   - playbook: a playbook in the tests directory (default = "test.yml")
#   - role_dir: the directory where the role exists (default = $PWD)
#   - cleanup: whether to remove the Docker container (default = true)
#   - container_id: the --name to set for the container (default = timestamp)
#   - test_idempotence: whether to test playbook's idempotence (default = true)
#
# If you place a requirements.yml file in tests/requirements.yml, the
# requirements listed inside that file will be installed via Ansible Galaxy
# prior to running tests.
#
# License: MIT

# Exit on any individual command failure.
set -e

# Pretty colors.
red='\033[0;31m'
green='\033[0;32m'
neutral='\033[0m'

timestamp=$(date +%s)

# Allow environment variables to override defaults.
distro=${distro:-"rockylinux8"}
playbook=${playbook:-"test.yml"}
role_dir=${role_dir:-"$PWD"}
cleanup=${cleanup:-"true"}
container_id=${container_id:-$timestamp}
test_idempotence=${test_idempotence:-"true"}

## Set up vars for Docker setup.
# Rocky Linux 9
if [ $distro = 'rockylinux9' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Rocky Linux 8
elif [ $distro = 'rockylinux8' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# CentOS 7
elif [ $distro = 'centos7' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Ubuntu 22.04
elif [ $distro = 'ubuntu2204' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Ubuntu 20.04
elif [ $distro = 'ubuntu2004' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Ubuntu 18.04
elif [ $distro = 'ubuntu1804' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Debian 12
elif [ $distro = 'debian12' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Debian 11
elif [ $distro = 'debian11' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Debian 10
elif [ $distro = 'debian10' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Fedora 38
elif [ $distro = 'fedora38' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Fedora 37
elif [ $distro = 'fedora37' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
# Fedora 36
elif [ $distro = 'fedora36' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --cgroupns=host --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw"
fi

# Run the container using the supplied OS.
printf ${green}"Starting Docker container: geerlingguy/docker-$distro-ansible."${neutral}"\n"
docker pull geerlingguy/docker-$distro-ansible:latest
docker run --detach --volume="$role_dir":/etc/ansible/roles/role_under_test:rw --name $container_id $opts geerlingguy/docker-$distro-ansible:latest $init

printf "\n"

# Install requirements if `requirements.yml` is present.
if [ -f "$role_dir/tests/requirements.yml" ]; then
  printf ${green}"Requirements file detected; installing dependencies."${neutral}"\n"
  docker exec --tty $container_id env TERM=xterm ansible-galaxy install -r /etc/ansible/roles/role_under_test/tests/requirements.yml
fi

printf "\n"

# Test Ansible syntax.
printf ${green}"Checking Ansible playbook syntax."${neutral}
docker exec --tty $container_id env TERM=xterm ansible-playbook /etc/ansible/roles/role_under_test/tests/$playbook --syntax-check

printf "\n"

# Run Ansible playbook.
printf ${green}"Running command: docker exec $container_id env TERM=xterm ansible-playbook /etc/ansible/roles/role_under_test/tests/$playbook"${neutral}
docker exec $container_id env TERM=xterm env ANSIBLE_FORCE_COLOR=1 ansible-playbook /etc/ansible/roles/role_under_test/tests/$playbook

if [ "$test_idempotence" = true ]; then
  # Run Ansible playbook again (idempotence test).
  printf ${green}"Running playbook again: idempotence test"${neutral}
  idempotence=$(mktemp)
  docker exec $container_id ansible-playbook /etc/ansible/roles/role_under_test/tests/$playbook | tee -a $idempotence
  tail $idempotence \
    | grep -q 'changed=0.*failed=0' \
    && (printf ${green}'Idempotence test: pass'${neutral}"\n") \
    || (printf ${red}'Idempotence test: fail'${neutral}"\n" && exit 1)
fi

# Remove the Docker container (if configured).
if [ "$cleanup" = true ]; then
  printf "Removing Docker container...\n"
  docker rm -f $container_id
fi

#!/bin/bash

# env vars:
#   AUTO_TRACE (automatic trace: default "20us")
#   DISABLE_CPU_BALANCE (default "n", choice y/n)

source common-libs/functions.sh

echo "############# dumping env ###########"
env
echo "#####################################"

echo "########## container info ###########"
echo "/proc/cmdline:"
cat /proc/cmdline
echo "#####################################"

echo "**** uid: $UID ****"
if [[ -z "${AUTO_TRACE}" ]]; then
    AUTO_TRACE="20"
fi

release=$(cat /etc/os-release | sed -n -r 's/VERSION_ID="(.).*/\1/p')

for cmd in rtla; do
    command -v $cmd >/dev/null 2>&1 || { echo >&2 "$cmd required but not installed. Aborting"; exit 1; }
done

# --------------------------------------------
cpulist=`get_isolated_cpuset`
echo "isolated cpu list: ${cpulist}"

uname=`uname -nr`
echo "$uname"

cpulist=`convert_number_range ${cpulist} | tr , '\n' | sort -n | uniq`

declare -a cpus
cpus=(${cpulist})

if [ "${DISABLE_CPU_BALANCE:-n}" == "y" ]; then
    disable_balance
fi

trap TERM INT SIGUSR1

cyccore=${cpus[1]}
cindex=2
ccount=1
while (( $cindex < ${#cpus[@]} )); do
    cyccore="${cyccore},${cpus[$cindex]}"
    cindex=$(($cindex + 1))
    ccount=$(($ccount + 1))
done

sibling=`cat /sys/devices/system/cpu/cpu${cpus[0]}/topology/thread_siblings_list | awk -F '[-,]' '{print $2}'`
if [[ "${sibling}" =~ ^[0-9]+$ ]]; then
    echo "removing cpu${sibling} from the cpu list because it is a sibling of cpu${cpus[0]} which will be the mainaffinity"
    cyccore=${cyccore//,$sibling/}
    ccount=$(($ccount - 1))
fi
echo "new cpu list: ${cyccore}"

command="rtla timerlat hist --auto ${AUTO_TRACE} --cpus ${cyccore} -e sched:sched_switch -e sched:sched_wakeup -e sched:sched_migrate_task -e irq -e irq_vectors -e timer -e workqueue"

echo "running cmd: ${command}"
if [ "${manual:-n}" == "n" ]; then
    $command
else
    sleep infinity
fi

sleep infinity

if [ "${DISABLE_CPU_BALANCE:-n}" == "y" ]; then
    enable_balance
fi

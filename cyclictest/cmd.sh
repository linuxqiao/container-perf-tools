#!/bin/bash

# env vars:
#   DURATION (default "24h")
#   DISABLE_CPU_BALANCE (default "n", choice y/n)
#   INTERVAL (default "1000")
#   stress (default "false", choices false/true)
#   rt_priority (default "1")
#   delay (default 0, specify how many seconds to delay before test start)
#   TRACE_THRESHOLD: stop cyclictest when threshold triggered (in usec); no default

source common-libs/functions.sh

echo "############# dumping env ###########"
env
echo "#####################################"

echo "########## container info ###########"
echo "/proc/cmdline:"
cat /proc/cmdline
echo "#####################################"

echo "**** uid: $UID ****"
if [[ -z "${DURATION}" ]]; then
    DURATION="24h"
fi

if [[ -z "${INTERVAL}" ]]; then
    INTERVAL="1000"
fi

if [[ -z "${rt_priority}" ]]; then
    rt_priority=1
elif [[ "${rt_priority}" =~ ^[0-9]+$ ]]; then
    if (( rt_priority > 99 )); then
        rt_priority=99
    fi
else
    rt_priority=1
fi

release=$(cat /etc/os-release | sed -n -r 's/VERSION_ID="(.).*/\1/p')

for cmd in cyclictest; do
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

if [[ -n "${TRACE_THRESHOLD}" ]]; then
    extra_opt="${extra_opt} -b ${TRACE_THRESHOLD} --tracemark"
fi

command="cyclictest -q -D ${DURATION} -p ${rt_priority} -t ${ccount} -a ${cyccore} -h 30 -i ${INTERVAL} --mainaffinity ${cpus[0]} -m ${extra_opt}"

echo "running cmd: ${command}"
if [ "${manual:-n}" == "n" ]; then
    if [ "${delay:-0}" != "0" ]; then
        echo "sleep ${delay} before test"
        sleep ${delay}
    fi
    $command
else
    sleep infinity
fi

sleep infinity

if [ "${DISABLE_CPU_BALANCE:-n}" == "y" ]; then
    enable_balance
fi

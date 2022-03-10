#!/bin/sh
<<comment
script: hostinfo.sh
scope: script to create driver & firmware report for i/o modules without generating logs
usage: create: hostinfo.sh in /tmp on the esxi, change permissions: chmod +x /tmp/hostinfo.sh, execute script: /tmp/hostinfo.sh
platform: ESXi 6.5, 6.7
version 1.0 - 2020-07-13
version 2.0 - 2020-08-18 - added datastore module, RAM info, and automated file creation
version 3.0 - 2020-09-10 - many changes, additions and improvements like loop for drivers
version 4.0 - 2020-09-25 - code enhancements
version 5.0 - 2020-10-02 - storage module enhancements
version 6.0 - 2020-10-02 - changed menu to avoid script not responding if host is in a non responsive state
version 7.0 - 2020-10-02 - tweaked the vm module
author: AK
if you require deep analysis, generate the host logs and review
use at your own risk
comment

clear
echo -e "\e[100m\e[1mHostinfo script for ESXi 6.5 & 6.7 v7.0\e[0m"

#input module

read -p "Are all datastores accessible and host responsive? [y/n] " STOPT
if [ "$STOPT" = "y" ] || [ "$STOPT" = "Y" ]; then
    read -p "Found $(df -h| egrep -wv "vfat|Filesystem"| wc -l) datastores's. Include in report? [y/n] " DSOPT
    if [ $(vim-cmd vmsvc/getallvms| sed '1d' 2>/dev/null| grep -v "Skipping"| wc -l) -gt 0 ]; then
        read -p "Found $(vim-cmd vmsvc/getallvms| sed '1d' 2>/dev/null| grep -v "Skipping"| wc -l) vm's. Include in report? [y/n] " VMOPT
    else
        VMOPT="n"
    fi
    read -p "Include last 10 to 20 storage events from vmkernel logs? [y/n] " STEVNT
else
    DSOPT="n"
    STOPT="n"
    VMOPT="n"
    STEVNT="n"
fi

read -p "Found $(esxcfg-vswitch -l| grep -w "Switch Name"| wc -l) Standard Switches, $(esxcfg-vswitch -l| grep -w "DVS Name"| wc -l) Distributed Switches and $(esxcfg-vmknic -l| egrep -vw "MAC Address"|wc -l) vmkernel portgroups. Include in report? [y/n] " VSOPT

#common function used in i/o modules
printv(){
    echo "VMware HCL page link below - compare drivers and firmware. If the VMware HCL combination does not match, contact the Server hardware team"  >> /tmp/$(hostname -f).txt
    lspci -p|grep -w $device| awk '{print "Driver:", $(NF-1)}' >> /tmp/$(hostname -f).txt
    lspci -p| grep -w $device| awk '{print $2, $3}'| sed 's/:/ /g'|
    awk '{print "https://www.vmware.com/resources/compatibility/search.php?deviceCategory=io&VID="$1"&DID="$2"&SVID="$3"&SSID="$4"&details=1"}'|
    sed 's/ //g' >> /tmp/$(hostname -f).txt
    echo >> /tmp/$(hostname -f).txt
}

#cleanup and create file in /tmp folder on the ESXi host
echo -en "Removing existing /tmp/$(hostname -f).txt ....... "
rm -rf /tmp/$(hostname -f).txt 2>/dev/null
echo -e "\e[32mdone\e[0m."
echo -en "Creating /tmp/$(hostname -f).txt ................ "
touch /tmp/$(hostname -f).txt
echo -e "\e[32mdone\e[0m."

#host summary module
echo "Hostinfo script for ESXi 6.5 & 6.7 v7.0" >> /tmp/$(hostname -f).txt
echo -en "Writing host summary .................................. "
echo -e "==========================================================" >> /tmp/$(hostname -f).txt
echo "Hostname: $(hostname -f)" >> /tmp/$(hostname -f).txt
echo "Date & Time: $(date)" >> /tmp/$(hostname -f).txt
echo "Host IP: $(hostname -i)" >> /tmp/$(hostname -f).txt
echo $(vmware -l) $(vmware -v| awk '{print $NF}') >> /tmp/$(hostname -f).txt
echo "Previous build: $(cat /altbootbank/boot.cfg | grep build| awk -F "=" '{print $2}')" >> /tmp/$(hostname -f).txt
esxcli software profile get| egrep -w "Name:|Vendor:|Creation"| sed 's/^ *//' >> /tmp/$(hostname -f).txt
esxcli hardware platform get| egrep -w 'Name:|\sSerial'| sed 's/^ *//' >> /tmp/$(hostname -f).txt
echo BIOS Info: $(smbiosDump| grep "BIOS Info:" -A30| egrep -w "Vendor:|Version:|Date:|System BIOS release:"| awk -F ":" '{print $1="",$0}'| sed 's/"//g') >> /tmp/$(hostname -f).txt
echo -e Processor: $(smbiosDump| grep "Processor Info:" -A15| egrep -w "Version:"| sort| uniq| awk -F ":" '{print $1="",$0}'| sed {'s/"//g'}{'s/(R)//g') X $(smbiosDump| grep "Processor Info:"| wc -l) >> /tmp/$(hostname -f).txt
echo -e "RAM:\n$(smbiosDump| grep  -w "Memory Device:" -A9| egrep "Part Number|Size"| grep -v "No Memory Installed"| uniq -c| awk '{print $1, "X", $3 $4}')" >> /tmp/$(hostname -f).txt
if [ "$STOPT" = "y" ] || [ "$STOPT" = "Y" ]; then
    echo "Boot Partition UUID: $(esxcfg-info -b)" >> /tmp/$(hostname -f).txt #https://kb.vmware.com/s/article/2014558
    esxcfg-info -e >> /tmp/$(hostname -f).txt
    if [ $(df -h| egrep -wv "vfat|Filesystem"| wc -l) -gt 0 ]; then
        echo "Number of datastores: $(df -h| egrep -wv "vfat|Filesystem"| wc -l)" >> /tmp/$(hostname -f).txt
    else    
        DSOPT="n"
    fi
    if [ $(cat /var/log/vmksummary.log| grep -i boot| wc -l) -gt 0 ]; then
        echo "Recent reboots:" >> /tmp/$(hostname -f).txt
        cat /var/log/vmksummary.log| grep -i boot| tail -5 >> /tmp/$(hostname -f).txt
    fi
fi
echo "Log folder: $(esxcli system syslog config get| grep -w "Output:"| awk '{print $NF}')" >> /tmp/$(hostname -f).txt
echo "Uptime: $(uptime| awk '{print $3}')"| sed 's/,//' >> /tmp/$(hostname -f).txt
echo -e "\e[32mdone\e[0m."

#ramdisk module
echo -en "Writing ramdisk info .................................. "
echo -e "\n======================== RAM DISK ========================\n" >> /tmp/$(hostname -f).txt
esxcli system visorfs ramdisk list >> /tmp/$(hostname -f).txt
echo -e "\e[32mdone\e[0m."

#vfat module
if [ "$STOPT" = "y" ] || [ "$STOPT" = "Y" ]; then
    echo -en "Writing vfat info ..................................... "
    echo -e "\n========================== VFAT ==========================\n" >> /tmp/$(hostname -f).txt
    df -h| egrep -w "vfat|Filesystem"| sed 's/\/vmfs\/volumes\///g'| sed 's/Mounted on/Mounted on \/vmfs\/volumes\//g' >> /tmp/$(hostname -f).txt
    echo -e "\e[32mdone\e[0m."
fi

#storage module
if [ "$DSOPT" = "y" ] || [ "$DSOPT" = "Y" ]; then
    #datastore module
    echo -en "Writing datastore info ................................ "
    echo -e "\n======================= DATASTORE ========================" >> /tmp/$(hostname -f).txt
    echo -e "Number of datastores: $(df -h| egrep -wv "vfat|Filesystem"| wc -l)\n" >> /tmp/$(hostname -f).txt
    esxcli storage vmfs extent list >> /tmp/$(hostname -f).txt
    if [ $(esxcli storage nfs list| wc -l) -gt 0 ]; then
        echo -e "\n$(esxcli storage nfs list)" >> /tmp/$(hostname -f).txt
    fi
    if [ "$(esxcli vsan datastore list| sed 's/^[[:space:]]*//g'| grep "Datastore UUID:"| awk '{print $3}')" != "" ]; then
        echo -e "\nvSAN information\n----------------" >> /tmp/$(hostname -f).txt
        echo $(esxcli vsan datastore list| sed 's/^[[:space:]]*//g'| grep UUID -A1| sed 's/User Friendly/-/') >> /tmp/$(hostname -f).txt
    fi
    echo -e "\n==================== DATASTORE SPACE =====================\n" >> /tmp/$(hostname -f).txt
    df -h| grep -wv vfat| sed 's/\/vmfs\/volumes\///g'| sed 's/Mounted on/Mounted on \/vmfs\/volumes\//g' >> /tmp/$(hostname -f).txt
    echo -e "\e[32mdone\e[0m."
    #vaai psp iops module
    echo -en "Writing vaai psp iops info ............................ "
    echo -e "\n===================== VAAI PSP IOPS ======================\n" >> /tmp/$(hostname -f).txt
    for vaai in $(esxcli storage vmfs extent list| egrep -v "UUID|----"| awk '{print $(NF-1)}')
        do
            echo -en $(esxcli storage core device vaai status get| grep $vaai -A6| sed '{s/ *//g}{s/:/: /g}{s/Status//g}{s/Name//g}'; 
            esxcli storage nmp device list| grep $vaai -A4| egrep -w "Type:|Policy:"| awk '{print $4}'; 
            esxcli storage nmp device list| grep $vaai -A5| grep iops| awk '{print $6}'| awk -F "," '{print $2}')"\n" >> /tmp/$(hostname -f).txt
        done
    echo -e "\e[32mdone\e[0m."
fi

#last 20 failed storage events module
if [ "$STEVNT" = "y" ] || [ "$STEVNT" = "Y" ]; then
    echo -en "Writing storage events ................................ "
    echo -e "\n================ PREVIOUS STORAGE EVENTS =================\n" >> /tmp/$(hostname -f).txt
    zcat /var/run/log/vmkernel.*.gz 2>/dev/null| egrep "failed H:???|state in doubt"| tail -10 >> /tmp/$(hostname -f).txt
    cat /var/run/log/vmkernel.log 2>/dev/null| egrep "failed H:???|state in doubt"| tail -10 >> /tmp/$(hostname -f).txt
    echo -e "\e[32mdone\e[0m."
fi

#virtual machine module
if [ "$VMOPT" = "y" ] || [ "$VMOPT" = "Y" ]; then
  echo -en "Writing virtual machine info .......................... "
  echo -e "\n===================== VIRTUAL MACHINE ====================\n" >> /tmp/$(hostname -f).txt
  vim-cmd vmsvc/getallvms| head -n1| sed 's/ \Annotation//' >> /tmp/$(hostname -f).txt
  vim-cmd vmsvc/getallvms| sed '1d' >> /tmp/$(hostname -f).txt
  echo -e "\nPower state of the vm's:\n" >> /tmp/$(hostname -f).txt
  for vm in $(vim-cmd vmsvc/getallvms| sed '1d' 2>/dev/null| grep -v "Skipping"| awk '{print $1}')
    do 
      echo -en "$(vim-cmd vmsvc/getallvms| sed -e '1d' -e 's/ \[.*$//' -e 's/[ \t]*$//' 2>/dev/null| grep -w "^$vm"): " >> /tmp/$(hostname -f).txt
      echo " "$(vim-cmd vmsvc/power.getstate $vm| egrep -vw "^Retrieved|^Skipping") >> /tmp/$(hostname -f).txt
    done
  echo -e "\e[32mdone\e[0m."
fi

#vSwitch module
if [ "$VSOPT" = "y" ] || [ "$VSOPT" = "Y" ]; then
    echo -en "Writing vSwitch info .................................. "
    echo -e "\n======================== VSWITCH =========================\n" >> /tmp/$(hostname -f).txt
    esxcfg-vswitch -l|  sed '{s/^ *//g;/^ *$/d}' >> /tmp/$(hostname -f).txt
    echo -e "\e[32mdone\e[0m."

#portgroup info module
    echo -en "Writing portgroup info ................................ "
    echo -e "\n=================== VMKERNEL PORTGROUP ===================\n" >> /tmp/$(hostname -f).txt
    esxcfg-vmknic -l >> /tmp/$(hostname -f).txt
    echo -e "\e[32mdone\e[0m."
fi

#software iscsi module
if [ $(esxcli storage core adapter list| egrep -w "iscsi_vmk|Capabilities|----"| wc -l) -gt 2 ]; then
    echo -en "Writing software iscsi info ........................... "
    echo -e "\n===================== SOFTWARE ISCSI =====================\n" >> /tmp/$(hostname -f).txt
    esxcli storage core adapter list| egrep -w iscsi_vmk >> /tmp/$(hostname -f).txt
    if [ "$VSOPT" = "y" ] || [ "$VSOPT" = "Y" ]; then
        echo -e "\nPort Binding:" >> /tmp/$(hostname -f).txt
        echo -en $(esxcli iscsi networkportal list| egrep "Vmknic"| sed 's/Vmknic: //g')"\n" >> /tmp/$(hostname -f).txt
    else
        echo -e "\nPort Binding:" >> /tmp/$(hostname -f).txt
        echo -en $(esxcli iscsi networkportal list| egrep "IPv|Vmknic"| sed '{s/ Mask//g}{s/Vmknic: //g}')"\n" >> /tmp/$(hostname -f).txt
    fi
    echo -e "\e[32mdone\e[0m."
fi

#sas controller module
if [ $(esxcli storage san sas list| wc -c) -gt 0 ]; then
    echo -en "Writing SAS controller info ........................... "
    echo -e "\n===================== SAS CONTROLLER =====================\n" >> /tmp/$(hostname -f).txt
    esxcfg-scsidevs -a| grep sas >> /tmp/$(hostname -f).txt
    echo -e "\e[32mdone\e[0m."
fi

#hba module
if [ $(esxcfg-scsidevs -a| egrep -vi "iSCSI|USB|hpsa"| wc -l) -gt 0 ]; then
    echo -en "Writing HBA info ...................................... "
    echo -e "\n========================= HBA ============================\n" >> /tmp/$(hostname -f).txt
    esxcfg-scsidevs -a| egrep -vi "iSCSI|USB|hpsa" >> /tmp/$(hostname -f).txt
    echo -e "\e[32mdone\e[0m."
fi

#NIC info module
echo -en "Writing NIC info ...................................... "
echo -e "\n========================= NIC ============================\n" >> /tmp/$(hostname -f).txt
esxcfg-nics -l >> /tmp/$(hostname -f).txt
echo >> /tmp/$(hostname -f).txt
echo -e "\e[32mdone\e[0m."

#sas controller driver module
ved="ved"
if [ $(esxcli storage san sas list| wc -c) -gt 0 ]; then
    echo -en "Writing SAS controller firmware/driver info ........... "
    echo -e "============= SAS CONTROLLER FIRMWARE/DRIVER =============\n" >> /tmp/$(hostname -f).txt
    for device in $(esxcli storage san sas list| grep -w "Device Name:"| awk '{print $3}')
        do
            dev=$(esxcfg-scsidevs -a| grep -w $device| awk '{print $2}')
            if [ $dev != $ved ]; then
                echo $(lspci -v| grep -w $device| awk '{print $1=$NF="", $0}'| awk -F ":" '{print $2}'|sed 's/^ \+//') >> /tmp/$(hostname -f).txt
                esxcli storage san sas list| grep -w $device -A11| egrep "Firmware|Driver Version"| sed 's/^ *//' >> /tmp/$(hostname -f).txt
                printv
                ved=$(esxcfg-scsidevs -a| grep -w $device| awk '{print $2}')
            fi
        done
    echo -e "\e[32mdone\e[0m."
fi

#hba driver module
if [ $(esxcfg-scsidevs -a| egrep -vi "iSCSI|USB|hpsa"| wc -l) -gt 0 ]; then
    ved="ved"
    echo -en "Writing HBA firmware/driver info ...................... "
    echo -e "================== HBA FIRMWARE/DRIVER ===================\n" >> /tmp/$(hostname -f).txt
    for device in $(esxcfg-scsidevs -a| egrep -vi "iSCSI|USB|hpsa"| awk '{print $1}')
        do
            #str=$(lspci -v| grep -w $device| awk '{print $1=$NF="",$0}'| sed 's/^ \+//')
            dev=$(esxcfg-scsidevs -a| grep -w $device| awk '{print $2}')
            if [ $dev != $ved ]; then
                if [ "$(lspci -v| grep -w $device| awk '{print $1=$NF="",$0}'| sed 's/^ \+//')" ]; then #[ "$str" ]
                    echo $(lspci -v| grep -w $device| awk '{print $1=$NF="", $0}'| awk -F ":" '{print $2}'| sed 's/^ *//') >> /tmp/$(hostname -f).txt
                    vmkload_mod -s $(esxcfg-scsidevs -a| grep -w $device| awk '{print $2}')| grep -i version| sed 's/^ \+//' >> /tmp/$(hostname -f).txt
                    /usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a| grep "$device" -B60| egrep -iw "Firmware|FW|ROM"| sed 's/^ \+//'| awk -F "," '{print $1}' >> /tmp/$(hostname -f).txt
                    printv
                else
                    echo -e $(esxcfg-scsidevs -a| grep -w $device| awk '{print "Driver: ", $2}') >> /tmp/$(hostname -f).txt
                    vmkload_mod -s $(esxcfg-scsidevs -a| grep -w $device| awk '{print $2}')| grep -i version| sed 's/^ *//' >> /tmp/$(hostname -f).txt
                    /usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a| grep -w $device -A9| grep -w "value:"| awk '{print "Driver:",$1="",$0}' >> /tmp/$(hostname -f).txt
                    /usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a| grep -w $device -A9| grep -w "FW"| sed 's/^ \+//' >> /tmp/$(hostname -f).txt
                    echo -e "Look at NIC firmware driver part for the VMware HCL link:" >> /tmp/$(hostname -f).txt
                    echo >> /tmp/$(hostname -f).txt
                fi
            ved=$(esxcfg-scsidevs -a| grep -w $device| awk '{print $2}')
            fi
        done
    echo -e "\e[32mdone\e[0m."
fi

#nic driver module
ved="ved"
echo -en "Writing NIC firmware/driver info ...................... "
echo -e "================== NIC FIRMWARE/DRIVER ===================\n" >> /tmp/$(hostname -f).txt
for device in $(esxcfg-nics -l| grep vmnic| awk '{print $1}')
    do
        dev=$(esxcfg-nics -l| grep -w $device| awk '{print $3}')
        if [ $dev != $ved ]; then
            echo $(lspci -v|grep -w $device| awk '{print $1=$NF="", $0}'| awk -F ":" '{print $2}'|sed 's/^ *//') >> /tmp/$(hostname -f).txt
            esxcli network nic get -n $device| grep  Version| grep -v "Info:"| sed 's/^ \+//g' >> /tmp/$(hostname -f).txt
            printv
            ved=$(esxcfg-nics -l| grep -w $device| awk '{print $3}')
        fi
    done
echo -e "\e[32mdone\e[0m."

echo -e "========================= DONE ===========================\n" >> /tmp/$(hostname -f).txt

#end module
echo -en "Cleaning up ........................................... "
rm /tmp/hostinfo.sh 2>/dev/null
echo -e "\e[32mdone\e[0m."
echo -en "Hostinfo file \e[100m\e[1m/tmp/$(hostname -f).txt\e[0m created successfully\n"



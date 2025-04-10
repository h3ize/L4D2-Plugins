Setup a cronjob to have this running in the background. I recommend running it on machine reboot.

"@reboot sleep 30 && /root/monitor_srcds.sh"

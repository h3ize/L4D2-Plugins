Setup a cronjob to have these running in the background. I recommend running it on machine reboot.

@reboot sleep 30 && /root/monitor_srcds.sh // To run on reboot
*/2 * * * *  /root/srcds_manager.sh // Check every 2 minutes

# weekly-maintenance
This is a bash script that integrates with home assistant andf performs routine OS updates and chackes reporting back to JAOS; it pass the status and upon any task failing, pr5ovides details and whats still to be completed.

The two files are to be copied to the following locations

weekly_maintenance.conf to /etc/
weekly_maintenance.sh to /usr/local/bin/

chmod +x /usr/local/bin/weekly_maintenance.sh

crontab -etc/
0 3 * * 0 /usr/local/bin/weekly_maintenance.sh


Check the variable dry run is correct in the .conf file before trying to run

Set the TZ if not qalready local/bin/0 3 * * 0 /usr/local/bin/weekly_maintenance.sh
ln -sf /usr/share/zoneinfo/[country/state-or-region] /etc/localtime

On home assistant
create a toggle helper called WM_<hostname>_status

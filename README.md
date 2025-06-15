# weekly-maintenance
This is a bash script that integrates with home assistant and performs routine OS updates and chackes reporting back to JAOS; it pass the status and upon any task failing, pr5ovides details and whats still to be completed.

HOWTO INSTALL
The two files are to be copied to the following locations:
  - weekly_maintenance.conf to /etc/
  - weekly_maintenance.sh to /usr/local/bin/

set the execute permission on the shell script
  chmod +x /usr/local/bin/weekly_maintenance.sh

Using the systen cron capability add an entry similar to the one below: 
  crontab -e
  0 3 * * 0 /usr/local/bin/weekly_maintenance.sh

REVISION MANAGEMENT
Check the variable dry run is correct in the .conf file before trying to run

GOOD PRACTISE
A few packages should be installed to make integration of a linux host easier
  apt install git sudo wget curl avahi-daemon
  
Set the TZ if not qalready local/bin/0 3 * * 0 /usr/local/bin/weekly_maintenance.sh
ln -sf /usr/share/zoneinfo/[country/state-or-region] /etc/localtime

HOME ASSISTANT AUTOMATION

alias: Weekly Maintenance Reports
description: ""
triggers:
  - trigger: webhook
    allowed_methods:
      - POST
      - PUT
    local_only: true
    webhook_id: Hro7I4IrvTocU0Imjf0VcUzm_working-maintenance
conditions: []
actions:
  - variables:
      hoststatus: input_boolean.wm_{{(trigger.json.Node)|lower|replace("-", "_")}}_status
    enabled: true
  - action: persistent_notification.create
    metadata: {}
    data:
      title: Received Webhook
      message: |-
        {{trigger.json}}

        {{hoststatus}}
    enabled: false
  - alias: report
    if:
      - condition: template
        value_template: "{{ trigger.json.Node is defined }}"
    then:
      - choose:
          - conditions:
              - alias: Status = Pass
                condition: template
                value_template: "{{ trigger.json.Status == \"Pass\" }}"
            sequence:
              - action: input_boolean.turn_on
                metadata: {}
                data: {}
                target:
                  entity_id: "{{hoststatus}}"
            alias: Pass
          - conditions:
              - alias: Status = Fail
                condition: template
                value_template: "{{ trigger.json.Status == \"Fail\" }}"
            sequence:
              - action: input_boolean.turn_off
                metadata: {}
                data: {}
                target:
                  entity_id: "{{hoststatus}}"
              - action: persistent_notification.create
                metadata: {}
                data:
                  message: >-
                    There was an issue reported from the weekly maintenance for
                    {{trigger.json.Node}} the information received was:


                    {{trigger.json}}
                  title: "Weekly Maintenance Error on {{trigger.json.Node}} "
            alias: Fail
        default:
          - action: persistent_notification.create
            metadata: {}
            data:
              message: >-
                There was an issue processing the weekly report the information
                received was:


                {{trigger.json}}
              title: Weekly Maintenance Task Error
mode: single




HOME ASSISTANT HELPER
On home assistant
create a toggle helper called WM_<hostname>_status

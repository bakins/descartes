#data bag where applications are stored
default[:descartes][:app_data_bag] = "descartes_applications"

#data bag where apps are "Scheduled"
default[:descartes][:sched_data_bag] = "descartes_schedule"

# where we deploy apps
default[:descartes][:app_dir] = "/etc/descartes/apps"

default[:descartes][:network] = "192.168.254.0/24"

include_recipe "apt"

# Have to set these files up before we install package or lxc starts with a bogus bridge
file "/etc/default/lxc" do
  owner "root"
  mode "0444"
  content <<EOF
USE_LXC_BRIDGE="false"
LXC_AUTO="false"
LXC_SHUTDOWN_TIMEOUT=120
EOF
end

package "lxc" do
  options '-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"'
end

service "lxc-net" do
  provider Chef::Provider::Service::Upstart
  action [ :stop ]
end

# should we just assume you have the correct kernel installed in your image
# as it requires a reboot

apt_repository "docker" do
  uri "http://ppa.launchpad.net/dotcloud/lxc-docker/ubuntu"
  distribution node['lsb']['codename']
  components ['main']
  keyserver "keyserver.ubuntu.com"
  key "63561DC6"
end

%w[ linux-image-generic-lts-raring linux-headers-generic-lts-raring lxc-docker ].each do |p|
  package p
end

cookbook_file "/etc/init/docker.conf" do
  notifies :restart, 'service[docker]', :immediately
end

service 'docker' do
  provider Chef::Provider::Service::Upstart
  supports :status => true, :restart => true, :reload => true
  action [ :start ]
end

chef_gem 'docker-api'
require 'docker'

class Docker::Container
  def running?
    json['State']['Running']
  end

  def delete
    connection.delete("/containers/#{self.id}")
  end

  def hostname
    json['Config']['Hostname']
  end
end

node.run_state[:descartes_apps] = []

data_bag(node[:descartes][:sched_data_bag]).each do |id|
  instance = data_bag_item(node[:descartes][:sched_data_bag], id)
  name = instance["id"] # id is general the app name + app version + an identifier which is unique per app version

  node.run_state[:descartes_apps] << { name: name, check: instance["check"] }

  # note - the instance contains a full copy of the app
  # because config may change between versions
  # we could create a new shared data bag item per app version??

  # TODO: write this LWRP
  descartes_container name do
    image instance["image"]
    command instance["command"]
    env instance["env"]
    port instance["port"]
    # TODO: any monitoring stuff we care about
    action :create
  end

  #TODO: announce in etcd??
end

Docker::Container.all(all: 1).each do |c|
  name = c.hostname
  unless c.running?
    Chef::Log.info "Deleting: #{c.id} : #{name}"
    c.delete
  end
  found = false
  node.run_state[:descartes_apps].each do |i|
    if c.hostname == i[:name]
      found = true
      break
    end
  end
  unless found
    descartes_container name do
      container_id c.id
      action :delete
    end
  end
end

# thinking of having a watchdog daemon that makes sure containers are running and does the registration with etcd
#just a directory of files is fine
#look at the directory and bounce if needed
ruby_block "collect docker ids" do
  block do
    Docker::Container.all.each do |c|
      node.run_state[:descartes_apps].each do |i|
        if c.hostname == i[:name]
          i[:id] = c.id
        end
      end
    end
  end
end

template "/etc/descartes-apps.yml" do
  
end

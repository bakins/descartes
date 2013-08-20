include_recipe "apt"
include_recipe "runit"

[ :app_dir, :log_dir ].each do |d|
  directory node[:descartes][d] do
    recursive true
  end
end

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

cookbook_file "/usr/local/sbin/docker-helper" do
  mode 0544
  source "docker-helper.rb"
end

apps = []

data_bag(node[:descartes][:sched_data_bag]).each do |id|
  instance = data_bag_item(node[:descartes][:sched_data_bag], id)
  name = instance["id"] # id is general the app name + app version + an identifier which is unique per app version

  apps << name

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

Dir.glob(File.join(node[:descartes][:app_dir], "*.yml")).map{|f| File.basename(f, ".yml")}.reject{|a| apps.include? a}.each do |a|
  descartes_container a do
    action :delete
  end
end

# we should also delete any docker containers that are not running?
# also, any images that aren;t being used?
# maybe do in a cron job?

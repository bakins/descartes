# this is really just a poor re-implementation of docker
# but using normal services and tar balls.
# once docker is more stable and has real private repo
# support, we should just switch

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

%w[ bridge-utils iptables-persistent lxc ].each do |p|
  package p do
    options '-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"'
  end
end

service "lxc-net" do
  provider Chef::Provider::Service::Upstart
  action [ :stop ]
end

require 'ipaddr'
ips = IPAddr.new(node[:descartes][:network]).to_range.map{|i| i.to_s}

#first ip is the network
ips.shift
#last ip is the broadcast
ips.pop

# we use first ip as gateway
gateway = ips.shift


template "/etc/init/descartes-net.conf" do
  variables(
            :addr => gateway,
            :network => node[:descartes][:network]
            )
  notifies :restart, "service[descartes-net]"
end

service "descartes-net" do
  provider Chef::Provider::Service::Upstart
  action [ :start ]
end

require 'yaml'

cookbook_file "/etc/init/loop-devices.conf" do
  notifies :restart, "service[loop-devices]"
end

service "loop-devices" do
  provider Chef::Provider::Service::Upstart
  action :start
end

# TODO: move to a library or LWRP?
directory node[:descartes][:app_dir]

#get a list of apps we are running
apps = Hash[*Dir.glob(node[:descartes][:app_dir] + "/*/.manifest").map{|f| [f.split("/")[-2], YAML.load_file(f)] }.flatten]

Chef::Log.info("Current Apps: " + apps.keys.join(", "))

#remove used ips
apps.each do |k,v|
  ips.delete(v["ip"])
end

#apps we need to remove
apps_to_delete = apps.dup

iptables_rules = {}

ports = (1025..65535).to_a

#search(node[:descartes][:sched_data_bag].to_sym, "node:#{node.name}") do |item|
#data_bag(node[:descartes][:sched_data_bag]).select{ |k,v| ["node"] == node.name}.each do |item|
data_bag(node[:descartes][:sched_data_bag]).each do |id|

  item = data_bag_item(node[:descartes][:sched_data_bag], id)
  app = data_bag_item(node[:descartes][:app_data_bag], item["app"])
  name = item["id"]

  dir = File.join(node[:descartes][:app_dir], name)
  app_dir = File.join(dir, 'app')
  log_dir = File.join(dir, 'log')
  manifest_file = File.join(dir, ".manifest")

  manifest = {}
  if apps[name] then
    # remove from list as we are deploying it
    apps_to_delete.delete(name)
    manifest = apps[name]
  else
    manifest["ip"] =  ips.shuffle.pop
    manifest["port"] = ports.shuffle.pop
  end

  [ dir, app_dir, log_dir ].each do |d|
    directory d
  end

  loopback = File.join(dir, "app.img")

  bash "create app filesystem for #{name}" do
    code <<EOF
truncate --size=#{app["disk_size"] || "1G"} #{loopback}
mkfs -t ext3 -F #{loopback}
EOF
    not_if { File.readable? manifest_file }
  end

  mount app_dir do
    device loopback
    options "loop,rw,noatime,nodiratime"
    fstype "ext3"
    action  [:mount, :enable]
  end

  #use the info from app to fetch the tarball and deploy it

  artifact = File.join(dir, File.basename(app["artifact_url"]))

  remote_file artifact do
    source app["artifact_url"]
    checksum app["artifact_checksum"]
    not_if { File.readable? manifest_file }
  end

  bash "extract #{artifact}" do
    code "tar -C #{app_dir} -xzf #{artifact} && rm #{artifact}"
    not_if { File.readable? manifest_file }
  end

  file manifest_file do
    content YAML.dump(manifest)
  end

  iptables_rules[manifest["port"]] = [ manifest["ip"], app["port"]].join(":")

  init_script = File.join(dir, "init")
  template init_script do
    mode 0555
    variables(
              :gateway => gateway,
              :command => app["command"],
              :env => {
                'PORT' => 5000
              }
              )
    notifies :restart, "service[#{name}]"
  end

  # directorie sthat must exist in contiainer
  %w[ etc proc sys dev/pts dev/shm sbin ].each do |d|
    directory File.join(app_dir, d) do
      recursive true
    end
  end

  # we bind mount over these files
  %w[ /etc/resolv.conf /sbin/init ].each do |f|
    file File.join(app_dir, f) do
      mode 0555
      content ""
    end
  end

  lxc_config =  File.join(dir, "lxc.config")
  template lxc_config do
    variables(
              :hostname => item,
              :ipaddress => manifest["ip"],
              :network => IPAddr.new(node[:descartes][:network]).to_range.first.to_s,
              :rootfs => app_dir,
              :init => init_script,
              :memory => app["memory"] || 268435456,
              :shares => app["shares"] || 100,
              :bridge => "lxcbr0"
              )
    notifies :restart, "service[#{name}]"
  end

  template "/etc/init/#{name}.conf" do
    source "lxc-upstart.conf.erb"
    variables(
             :name => name,
             :config => lxc_config
             )
    notifies :restart, "service[#{name}]"
  end

  service name do
    provider Chef::Provider::Service::Upstart
    action :start
  end

  #could setup log shipper to grab any other logs we need??
end

#Chef::Log.info("Apps to delete: " + apps_to_delete.join(", "))

#delete any apps we shouldn't be running
#apps_to_delete.each do |app|
#  dir = File.join(node[:descartes][:app_dir], app)
#  app_dir = File.join(dir, 'app')
#  loopback = File.join(dir, "app.img")

#  mount app_dir do
#    device loopback
#    action [ :disable, :umount ]
#    only_if { File.readable? loopback }
#  end

  #need to shutdown jobs, etc
#  directory dir do
 #    action :delete
#    recursive true
#  end
#end

template "/etc/iptables/rules.v4" do
  source "iptables.conf.erb"
  variables(
            :address => node[:ipaddress],
            :rules => iptables_rules,
            :network => node[:descartes][:network]
            )
  notifies :restart, "service[iptables-persistent]", :immediately
end

service "iptables-persistent" do
  supports :restart => true, :reload => true
  action [ :enable, :start ]
end

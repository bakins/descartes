Vagrant.configure("2") do |config|
  config.ssh.forward_agent = true
  config.vm.box = "docker"
  #config.vm.box_url = "http://files.vagrantup.com/precise64.box"
  config.omnibus.chef_version = "11.6.0"
  config.vm.provision :chef_solo do |chef|
    chef.data_bags_path = "data_bags"
    chef.run_list = [
                     "recipe[descartes::worker]"
                    ]
  end
end


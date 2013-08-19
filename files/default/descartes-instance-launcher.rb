#!/opt/chef/embedded/bin/ruby
require 'docker'
require 'yaml'
require 'net/http'

config = YAML.load_file(ARGV[0] || '/etc/descartes-apps.yml')

while true do
  config['instances'].each do |i|
    puts "checking #{i['name']}"
    # first make sure it's even running
    Docker::Container.all.each do |c|
      if c.id == i['id']
        data = c.json
        unless data['State']['Running']
          puts "starting #{i['name']} : #{c.id}"
          c.start
          sleep 5
        end
        # now check the url if availible
        # if it passes, announce to etcd
        http = Net::HTTP.new(data['NetworkSettings']['IPAddress'], data['Config']['PortSpecs'].first.to_i)
        http.read_timeout = 5000
        if i['check']
          begin
            rc = http.get(i['check'])
          rescue => e
            puts "#{i['name']} : #{c.id} : #{e}"
            rc = nil
          end
          if rc
            #announce to etcd with an expire time
          end
        end
      end
    end
  end

  #TODO sleep for less than a minute or somethign
  sleep 10
end

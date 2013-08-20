actions :create, :delete
default_action :create

attribute :instance, :kind_of => String, :name_attribute => true
attribute :image, :kind_of => String, :required => true
attribute :command, :kind_of => Array
attribute :env, :kind_of => Hash, :default => {}
attribute :port, :kind_of => Integer, :default => 5000
attribute :container_id, :kind_of => String

user 'courier_admin' do
  comment 'Courier Admin User'
  home '/home/courier_admin'
  shell '/bin/bash'
  manage_home true
  password '$1$U6n/t.DZ$x0sX58ZesfaPlJkdatG.i0'
  action :create
end

user 'inspec_admin' do
  comment 'Inspec Admin User'
  home '/home/inspec_admin'
  shell '/bin/bash'
  manage_home true
  password '$1$U6n/t.DZ$x0sX58ZesfaPlJkdatG.i0'
  action :create
end

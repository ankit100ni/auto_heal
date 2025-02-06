# controls/package_test.rb

control 'package-01' do
  impact 1.0
  title 'Verify if curl is installed'
  desc 'Check if the curl package is installed on the system'

  describe package('curl') do
    it { should be_installed }
  end
end

# controls/user_test.rb

control 'user-01' do
  impact 1.0
  title 'Verify if ubuntu user exists'
  desc 'Ensure the user ubuntu is present on the system'

  describe user('ubuntu') do
    it { should exist }
  end

  describe user('courier_admin') do
    it { should exist }
  end
end

# controls/user_test.rb

control 'package-02' do
  impact 1.0
  title 'Verify if ubuntu package exists'
  desc 'Ensure the user ubuntu is present on the system'

  describe package('dummy') do
    it { should be_installed }
  end
end

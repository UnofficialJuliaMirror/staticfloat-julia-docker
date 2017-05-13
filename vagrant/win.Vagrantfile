# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
    # Define "buildworker" vm which gets the royal treatment with everything you can imagine fed into it
    config.vm.define "buildworker" do |worker|
        worker.vm.box = "{box_name}"
        worker.vm.provider "virtualbox" do |vb|
            vb.cpus = 4
            vb.memory = 8192
        end
        worker.vm.provision "file", source: "lib/secret/win.p12", destination: "C:/Users/vagrant/julia.p12"
        worker.vm.provision "file", source: "lib/secret/buildbot_secret.sh", destination: "C:/Users/vagrant/secret.sh"
        worker.vm.provision "file", source: "lib/buildbot_setup.sh", destination: "C:/Users/vagrant/buildbot_setup.sh"
        worker.vm.provision "shell", path: "lib/install_cygwin_and_friends.ps1", args: "{arch} {buildworker_name}", upload_path: "C:/Users/vagrant/install.ps1", run: "always"
    end
end

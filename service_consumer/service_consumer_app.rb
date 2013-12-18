require 'sinatra'
require 'json'

class ServiceConsumerApp < Sinatra::Base

  #declare the routes used by the app

  get "/" do
    #response_body = messages

    credentials_list = credentials_of_all_repos
    repo_uris = credentials_list.map { |c| c["uri"]} unless credentials_list.nil?

    erb :index, locals: { repo_uris: repo_uris, messages: messages }
  end

  get "/env" do
    content_type "text/plain"

    response_body = "VCAP_SERVICES = \n#{ENV["VCAP_SERVICES"]}"
    response_body << messages
    response_body
  end


  # TODO remove this
  get "/create_commit" do
    create_commit
  end

  # helper methods
  private

  def create_commit
    repo_credentials = credentials_of_all_repos[0]
    private_key = repo_credentials["private_key"]
    repo_name = repo_credentials["name"]
    repo_uri = repo_credentials["uri"]
    repo_ssh_url = repo_credentials["ssh_url"]
    keys_dir = "/tmp/github_keys"
    key_file_name = "#{keys_dir}/#{repo_name}.key"
    results = "REPO URI: #{repo_uri}\n"
    git_ssh_script = "/tmp/#{repo_name}_ssh_script.sh"
    known_hosts_file = "/tmp/github_known_hosts"

    # write key to file
    # set git author (and any other relevant config)
    # clone (via ssh-agent using deploy key)
    # create commit
    # push commit (via ssh-agent using deploy key)
    # delete deploy key
    # delete cloned directory

    `if [ ! -d #{keys_dir} ]; then mkdir #{keys_dir}; chmod 0700 #{keys_dir}; fi`

    # Store the private key in a file
    File.open(key_file_name, "w", 0600) do |f|
      f.puts private_key
    end

    # Create a unique known hosts file with github's public key, for these purposes:
    # 1) since SSH StrictHostKeyChecking is "on" by default, this file prevents SSH from asking the user to
    # confirm github.com's public key fingerprint upon first connection.
    # 2) not relying on the default ~/.ssh/known_hosts file
    File.open(known_hosts_file, "w", 0700) do |f|
      f.puts <<TEXT
github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==
TEXT
    end

    # Configure git to use this ssh setup instead of the default "ssh" command
    File.open(git_ssh_script, "w", 0700) do |f|
      f.puts <<BASH
#!/bin/sh
exec `which ssh` -o UserKnownHostsFile=#{known_hosts_file} -o HashKnownHosts=no -i #{key_file_name} "$@"
BASH
    end

    if credentials_are_valid?(repo_credentials)
      commands = [
          #"cat #{known_hosts_file}",
          "cd /tmp; GIT_SSH=#{git_ssh_script} git clone #{repo_ssh_url}",
          #"cat #{known_hosts_file}",
          "cd /tmp/#{repo_name} && git config user.name 'Demo App'",
          "cd /tmp/#{repo_name} && git commit --allow-empty -m 'auto generated empty commit'",
          "cd /tmp/#{repo_name} && git log",
          "cd /tmp/#{repo_name}; GIT_SSH=#{git_ssh_script} git push"
      ]

      #full_command = commands.join(" && ")
      #result << `#{full_command}`

      commands.each do |command|
        results << "\n\n> #{command}\n"
        results << `#{command}`
        return_code = $?
        puts "return code: #{return_code}"
        break if return_code != 0
      end

      # Remove the temp files regardless of success or failure
      cleanup_commands = [
          "rm #{key_file_name}", ## TODO: extract cleanup commands and run them always
          "rm #{git_ssh_script}",
          "rm -rf /tmp/#{repo_name}"
      ]

      cleanup_commands.each do |command|
        results << "\n\n> #{command}\n"
        results << `#{command}`
      end


      puts results

      content_type "text/plain"
      results
    end
  end

  def credentials_are_valid?(credentials)
    !(credentials["name"].empty?)
  end

  def messages
    result = ""
    result << "#{no_bindings_exist_message}" unless bindings_exist
    result << "\n\nAfter binding or unbinding any service instances, restart this application with 'cf restart [appname]'."
    result
  end

  def vcap_services
    ENV["VCAP_SERVICES"]
  end

  def bindings_exist
    JSON.parse(vcap_services).keys.any? { |key|
      key == service_name
    }
  end

  def no_bindings_exist_message
    "\n\nYou haven't bound any instances of the #{service_name} service."
  end

  def service_name
    "github-repo"
  end

  def credentials_of_all_repos
    if bindings_exist
      JSON.parse(vcap_services)[service_name].map do |service_instance|
        service_instance["credentials"]
      end
    end
  end


end

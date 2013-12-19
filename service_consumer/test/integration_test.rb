require File.expand_path '../test_helper.rb', __FILE__
require File.expand_path '../integration_test_helper.rb', __FILE__

describe "/" do
  before do
    @vcap_services_value = <<JSON
      {
        "github-repo": [
          {
            "name": "github-repo-1",
            "label": "github-repo-n/a",
            "plan": "public",
            "credentials": {
              "name": "#{repo_name}",
              "uri": "#{repo_uri}",
              "ssh_url": "#{repo_ssh_url}",
              "private_key": "#{repo_private_key}"
            }
          }
        ]
      }
JSON

    ServiceConsumerApp.any_instance.stubs(:vcap_services).returns(@vcap_services_value)

    visit "/"
  end

  it "has links to the repos" do
    page.must_have_link(repo_uri)
  end

  it "creates a commit when the commit button is clicked" do
    initial_commit_count = count_commits_in_repo
    click_on "Create a commit"
    sleep(2)
    final_commit_count = count_commits_in_repo

    assert_equal initial_commit_count + 1, final_commit_count
  end
end


private

def count_commits_in_repo
  github_client.commits(repo_fullname).length
end

def username
  ENV["GITHUB_USERNAME"]
end

def repo_name
  ENV["GITHUB_REPO_NAME"]
end

def repo_private_key
  ENV["GITHUB_REPO_PRIVATE_KEY"]
end

def repo_ssh_url
  "git@github.com:#{username}/#{repo_name}.git"
end

def repo_uri
  "https://github.com/#{username}/#{repo_name}"
end

def repo_fullname
  "#{username}/#{repo_name}"
end

def github_client
  ::Octokit::Client.new(login: ENV["GITHUB_USERNAME"], password: ENV["GITHUB_PASSWORD"])
end
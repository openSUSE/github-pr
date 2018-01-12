require_relative "../githubclient.rb"
require "rspec"
require "spec_helper"

describe GithubClient do
  before { stub_request(:any, /api.github.com/).to_rack(FakeGitHub.new(FILTERS4)) }
  METADATA = {
    org_repo: "openSUSE/github-pr",
    organization: "openSUSE",
    repository: "github-pr",
    context: "ruby/rspec"
  }

  it "can fetch 5 pull requsts" do
     pulls = GithubClient.new(METADATA).all_pull_requests(:open)
     expect(pulls.size).to eq(5)
  end

end

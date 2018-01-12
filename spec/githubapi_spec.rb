require_relative "../githubapi.rb"
require "rspec"
require "spec_helper"

describe GithubAPI do

  let(:githubapi) { GithubAPI.new }

  it "caches the octokit client" do
    othergithubapi = GithubAPI.new
    expect(githubapi.client).to equal(othergithubapi.client)
  end

end

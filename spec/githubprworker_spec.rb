require_relative "../githubprworker.rb"
require "rspec"
require "spec_helper"
require "yaml"


describe GithubPRWorker do

  context "no filter" do
    #let(:test_name) { NOFILTER }
    before { stub_request(:any, /api.github.com/).to_rack(FakeGitHub.new(NOFILTER)) }

    it "creates a nonfilter chain" do
       c_file = config_file(NOFILTER)
       yaml_config = YAML.load_file(c_file)
       pulls = GithubPRWorker.new({ config: c_file }, yaml_config).get_pulls
       expect(pulls.size).to eq(5)
    end
  end

  context "4 filters" do
    before { stub_request(:any, /api.github.com/).to_rack(FakeGitHub.new(FILTERS4)) }

    it "creates a 4 filter chain" do
       c_file = config_file(FILTERS4)
       yaml_config = YAML.load_file(c_file)
       pulls = GithubPRWorker.new({ config: c_file, debugfilterchain: false }, yaml_config).get_pulls
       expect(pulls.size).to eq(1)
       expect(pulls[0]["number"]).to eq(1)
    end
  end

end

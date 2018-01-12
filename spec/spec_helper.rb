require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

require_relative "../interactions/default"
require_relative "./support/fake_github"

NOFILTER = "nofilter".freeze
FILTERS4 = "4filters".freeze

def config_file(name)
  File.join(File.dirname(__FILE__), "support/fixtures/#{name}_config.yaml")
end

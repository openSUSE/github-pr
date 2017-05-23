require 'octokit'

class GithubAPI
  def create_client
    client = Octokit::Client.new(netrc: true)
    client.auto_paginate = true
    client.login
    client
  end

  def client
    @@client ||= create_client
  end

  def current_rate_limit
    client.rate_limit.remaining
  end
end

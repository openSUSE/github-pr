#!/usr/bin/ruby

require_relative 'githubapi'

class GithubClient
  RESULT_MESSAGES = {
    success: 'succeeded',
    failure: 'failed',
    error:   'has an error',
    pending: 'is pending',
  }

  def initialize(conf = {})
    @config = conf
  end

  def organization
    @config[:organization]
  end

  def repository
    @config[:repository]
  end

  def org_repo
    "#{organization}/#{repository}"
  end

  def context
    @config[:context]
  end

  def create_status(commit, details)
    result = details["status"].to_sym
    GithubAPI.new.client.create_status(
      org_repo,
      commit,
      result,
      { context: context,
        description: status_description(details["message"], result),
        target_url: details["target_url"].to_s
      }
    )
  end

  def status_description(description, status)
    description ||= RESULT_MESSAGES[status]
    description.to_s
  end

  def full_sha_status(sha)
    begin
      status = GithubAPI.new.client.status(org_repo, sha)
      status.statuses.select{ |s| s.context == context }.first || {}
    rescue
      {}
    end
  end

  def sha_status(sha)
    full_sha_status(sha).state rescue ""
  end

  def pull_request(pull)
    GithubAPI.new.client.pull_request(org_repo, pull)
  end

  def pull_info(pull)
    pull_request(pull).to_attrs
  end

  def pull_latest_sha(pull)
    pull_request(pull).head.sha rescue ''
  end

  def latest_sha?(pull, sha)
    pull_latest_sha(pull) == sha
  end

  # state = [:open|:closed]
  def all_pull_requests(state)
     GithubAPI.new.client.pull_requests(org_repo, state: state.to_s)
  end
end

#!/usr/bin/ruby

require 'optparse'
require 'yaml'

require_relative 'githubclient'
require_relative 'githubprworker'

## options
base_para = {}
options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Tool to trigger mkcloud builds for open pull requests and set the pull request status"
  opts.on("-h", "--help", "Show usage") do
    puts opts
    exit
  end
  opts.separator ""
  opts.separator "Parameters to process PR list"
  opts.on("-c", "--config CONFIG_FILE", "File with configuration and filter specification") do |c|
    base_para[:config] = c
  end
  opts.on("-a", "--action TYPE", "Action to perform, processing: [trigger-prs list-prs] ; " \
          "single PR: [set-status get-latest-sha is-latest-sha pr-info]"
         ) do |a|
    base_para[:action] = a
  end
  opts.on("-m", "--mode MODE", "Override the 'Status' filter definition(s) in the config file: [unseen rebuild forcerebuild all]") do |o|
    base_para[:mode] = o
  end
  opts.on("--only", "Process only ORG/REPO from the configuration file that are defined with --org and --repo. Default is to process all repos.") do
    base_para[:only_one_repo] = true
  end
  opts.on("-i", "--interaction_dirs DIR1,DIR2,DIR3", "Directories with interaction files to require. All files 'ia_*.rb' are included from these directories.") do |i|
    base_para[:interaction_dirs] = i.split(",")
  end
  opts.on("-d", "--debugfilterchain", "Debug the filterchain of the config file. Lists PRs after each filter step.") do
    base_para[:debugfilterchain] = true
  end
  opts.on("-l", "--debugratelimit", "Debugging API rate limit. Print the Github API rate limit to STDERR before and after processing the action.") do
    base_para[:debugratelimit] = true
  end

  opts.separator ""
  opts.separator "Parameters to set/query a github status"
  opts.on("-o", "--org ORG", "Github Organisation/Repository") do |o|
    options[:organization] = o
  end
  opts.on("-r", "--repo REPO", "Github Organisation/Repository") do |r|
    options[:repository] = r
  end
  opts.on("-x", "--context context-string", "Github Status Context String") do |x|
    options[:context] = x
  end
  opts.on("-p", "--pr PRID", "Github Status Context String") do |p|
    options[:pr] = p
  end
  opts.on("-u", "--sha SHA1SUM", "Github Commit SHA1 Sum") do |u|
    options[:sha] = u
  end
  opts.on("-t", "--targeturl URL", "Target URL of a CI Build; optional.") do |t|
    options[:target_url] = t
  end
  opts.on("-s", "--status STATUS", "Github Status of a CI Build [pending,success,failure,error]") do |s|
    options[:status] = s
  end
  opts.on("-e", "--message MSG", "Message to show in github next to the status; optional.") do |e|
    options[:message] = e
  end

  opts.separator ""
  opts.separator "Parameter for JSON query"
  opts.on('-k', '--key KEY',
          'Dot-separated attribute path to extract from PR JSON, e.g. base.head.owner. ' \
          'Only for use with pr-info action.') do |k|
    options[:key] = k
  end
end
optparse.parse!

## config
yaml_config = {}

if base_para[:config] then
  begin
    yaml_config = YAML.load_file(base_para[:config]) if base_para.has_key?(:config)
    yaml_base_path = File.dirname(base_para[:config])
  rescue Psych::SyntaxError
    puts "Error: Invalid YAML syntax in config file: #{base_para[:config]}"
    exit 2
  end

  ## include interaction files
  relative_interaction_dir = File.join(File.dirname(__FILE__), "interactions")
  require File.join(relative_interaction_dir, "default.rb")
  interaction_dirs = [ relative_interaction_dir ]

  base_para[:interaction_dirs].each do |dir|
    interaction_dirs.push(dir) if File.directory?(dir)
  end if base_para[:interaction_dirs].is_a?(Array)

  yaml_config["interaction_dirs"].each do |dir|
    new_dir = File.join(yaml_base_path, dir)
    interaction_dirs.push(new_dir) if File.directory?(new_dir)
  end if yaml_config["interaction_dirs"].is_a?(Array)

  interaction_dirs.collect{ |d| d.gsub(/\/+$/, "") rescue next}.compact.uniq.each do |dir|
    begin
      onedir = Dir.new(dir)
      Dir.glob(File.expand_path(File.join(onedir, 'ia_*.rb'))).each do |f|
        require f
      end
    rescue Errno::ENOENT
      raise "Could not find directory: #{dir}"
    end
  end
end

## helpers for parameter checks
def require_parameter(param, message)
  if param.to_s.empty?
    abort message
  end
end

def prevent_parameter(param, message)
  unless param.to_s.empty?
    abort message
  end
end

def debug_api_rate_limit(base_para)
  return unless base_para.has_key?(:debugratelimit) && base_para[:debugratelimit] == true
  STDERR.puts "API rate limit: " + GithubAPI.new.current_rate_limit.to_s
end

if base_para[:only_one_repo]
  require_parameter(options[:organization], 'Organization undefined.')
  require_parameter(options[:repository], 'Repository undefined.')
  base_para[:only_repo] = "#{options[:organization]}/#{options[:repository]}"
end

## main
debug_api_rate_limit(base_para)
case base_para[:action]
  when "list-prs"
    require_parameter(base_para[:config], 'Config file not defined.')
    GithubPRWorker.new(base_para, yaml_config).list_pulls
  when "trigger-prs"
    require_parameter(base_para[:config], 'Config file not defined.')
    GithubPRWorker.new(base_para, yaml_config).trigger_pulls
  when "set-status"
    prevent_parameter(base_para[:config], 'Config file should not be defined for this action.')
    require_parameter(options[:organization], 'Organization undefined.')
    require_parameter(options[:repository], 'Repository undefined.')
    require_parameter(options[:context], 'Context undefined.')
    require_parameter(options[:sha], 'SHA1 sum undefined.')
    require_parameter(options[:status], 'Status undefined.')
    GithubClient.new(options).create_status(options[:sha], {
      "status" => options[:status],
      "message" => options[:message],
      "target_url" => options[:target_url]
    })
  when "pr-info"
    prevent_parameter(base_para[:config], 'Config file should not be defined for this action.')
    require_parameter(options[:organization], 'Organization undefined.')
    require_parameter(options[:repository], 'Repository undefined.')
    require_parameter(options[:pr], 'PullRequest ID undefined.')
    data = GithubClient.new(options).pull_info(options[:pr])
    if options[:key]
      options[:key].split(/(?<!\\)\./).each do |key|
        key = key.to_sym
        if data.has_key? key
          data = data[key]
        else
          abort "No key '#{key}' in PR JSON:\n#{JSON.pretty_generate(data)}"
        end
      end
    end
    puts data.is_a?(Hash) ? JSON.pretty_generate(data) : data
  when "is-latest-sha"
    prevent_parameter(base_para[:config], 'Config file should not be defined for this action.')
    require_parameter(options[:sha], 'Commit SHA1 sum undefined.')
    require_parameter(options[:pr], 'PullRequest ID undefined.')
    require_parameter(options[:organization], 'Organization undefined.')
    require_parameter(options[:repository], 'Repository undefined.')
    exit GithubClient.new(options).latest_sha?(options[:pr], options[:sha]) ? 0 : 1
  when "get-latest-sha"
    prevent_parameter(base_para[:config], 'Config file should not be defined for this action.')
    require_parameter(options[:pr], 'PullRequest ID undefined.')
    require_parameter(options[:organization], 'Organization undefined.')
    require_parameter(options[:repository], 'Repository undefined.')
    puts GithubClient.new(options).pull_latest_sha(options[:pr])
end
debug_api_rate_limit(base_para)

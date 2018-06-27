#
# Github_PR default interactions (filter and action classes)
#
# github_pr.rb first requires this default.rb file,
# then all files in the interaction_dirs that match "ia_*.rb" (ia = interaction)
# The interaction_dirs can be defined in the yaml config as:
#   interaction_dirs:
#     - ./dir1
#     - /other/dir2
# or as command line parameter
#   --interaction_dirs ./dir1,/other/dir2
#

module GithubPR
  class Interaction
    def initialize(metadata, config = {})
      @metadata = metadata
      @c = config
    end

    def is_dryrun?
      @metadata[:dryrun] == true
    end
  end

  class Filter < Interaction
    def filter(pulls)
      pulls.partition do |pull|
        filter_applies?(pull)
      end
    end

    def filter_applies?(_pull)
      true
    end
  end

  class Action < Interaction
    def run(pulls)
      pulls.each do |pull|
        action(pull)
      end
    end

    def action(_pull)
      true
    end

    def system_cmd(*cmds)
      cmds.flatten!
      if is_dryrun?
        STDERR.puts "DRYRUN: #{cmds.join(' ')}"
        return true
      else
        system(*cmds) or false
      end
    end
  end


  #=== Filter Classes =======>>

  class FileMatchFilter < Filter
    def filter_applies?(pull)
      match_files = GithubAPI.new.client.pull_request_files(@metadata[:org_repo], pull[:number]).select do |f|
        @c["paths"].find do |path|
          path.match(f[:filename])
        end
      end
      match_files.size > 0
    end
  end

  class TrustedSourceFilter < Filter
    @@members = {}

    def team_members(team_id)
      # only query when needed - and cache in class variable
      @@members[team_id] ||= GithubAPI.new.client.team_members(team_id).map{|m| m["login"]} rescue {}
    end

    def team_member?(team_id, login)
      team_members(team_id).include?(login)
    end

    def allowed_user?(user)
      if @c.key?("users")
        return @c["users"].include?(user)
      end
      false
    end

    def allowed_team?(user)
      if @c.key?("teams")
        @c["teams"].each do |team|
          return true if team_member?(team["id"], user)
        end
        return false
      end
      false
    end

    def trusted_pull_request_source?(user)
      return false if (!user || user.nil? || user.empty?)
      return true if (allowed_user?(user) || allowed_team?(user))
      false
    end

    def filter_applies?(pull)
      user = pull.head.repo.owner.login rescue ''
      trusted_pull_request_source?(user)
    end
  end

  class MergeBranchFilter < Filter
    def filter_applies?(pull)
      @c["branches"].include?(pull.base.ref)
    end
  end

  class ThisPullRequestFilter < Filter
    def filter_applies?(pull)
      begin
        @c[:organization] == pull.base.repo.owner.login &&
          @c[:repository] == pull.base.repo.name &&
          @c[:pr]         == pull.number.to_s &&
          @c[:sha]        == pull.head.sha
      rescue
        false
      end
    end
  end

  class StatusFilter < Filter
    PULL_REQUEST_STATUS = {
      "unseen"       => [''],
      "rebuild"      => ['', 'pending'],
      "forcerebuild" => ['', 'pending', 'error', 'failure'],
      "all"          => ['', 'pending', 'error', 'failure', 'success'],
    }

    def filter_applies?(pull)
      stati = PULL_REQUEST_STATUS[@c["status"]] rescue ['']
      stati.include?(GithubClient.new(@metadata).sha_status(pull.head.sha))
    end
  end

  #=== Action Classes ========>>

  class SetStatusAction < Action
    def action(pull)
      if is_dryrun?
        STDERR.puts "DRYRUN: Not setting status for commit: #{pull.head.sha}"
      else
        GithubClient.new(@metadata).create_status(pull.head.sha, @c)
      end
    end
  end

  class LogPullRequestDetailsAction < Action
    def action(pull)
      # logging to stdout
      puts <<-HEREDOC

Processing #{pull.base.repo.full_name} PR id #{pull.number} by #{pull.head.user.login}
  SHA1: #{pull.head.sha}
  Title: #{pull.title}
  Link: #{pull.html_url}
      HEREDOC
    end
  end

  class RunCommandAction < Action
    def action(_pull)
      cmd = command + parameters
      system_cmd(cmd)
    end

    def command(key = "command")
      cmd = @c[key] or raise
      relative_cmd = File.join(@metadata[:config_base_path], cmd)
      return [relative_cmd] if File.exist?(relative_cmd)
      [cmd]
    end

    def parameters(key = "parameters")
      return @c[key] if @c.key?(key) && @c[key].is_a?(Array)
      []
    end
  end

  class RunHelperAndSetStatusAction < RunCommandAction
    def action(pull)
      cmd = command
      cmd += %W[
                github.com
                #{pull.base.repo.owner.login}
                #{pull.base.repo.name}
                #{pull.number}
                #{pull.head.sha}
                #{pull.head.user.login}
               ]
      res = system_cmd(cmd)
      status = res ? "success":"failure"
      conf = {
        "status" => status,
        "message" => "result: #{status}"
      }
      conf["target_url"] = ENV["BUILD_URL"] if ENV["BUILD_URL"]
      SetStatusAction.new(@metadata, conf).action(pull)
    end
  end
end

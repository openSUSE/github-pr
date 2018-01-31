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
        return true if @c["users"].include?(user)
      end
      false
    end

    def allowed_team?(user)
      if @c.key?("teams")
        return true if @c["teams"].find do |team|
          team_member?(team["id"], user)
        end
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
      GithubClient.new(@metadata).set_status(pull.head.sha, @c)
    end
  end

  class RunCommandAction < Action
    def action(_pull)
      cmd = command + parameters
      system(*cmd) or raise
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
end

require "sinatra/base"

class FakeGitHub < Sinatra::Base
  def initialize(test_name)
    super
    @test_name = test_name
  end

  get "/repos/:organization/:project/pulls" do
    json_response 200, "pulls.small"
  end

  get "/repos/:organization/:project/pulls/:id/files" do
    json_response 200, "pulls.#{params[:id]}.files"
  end

  get "/repos/:organization/:project/commits/:sha1/status" do
    json_response 200, "commits.#{params[:sha1]}.statuses"
  end

  get "/teams/:id/members" do
    json_response 200, "team.#{params[:id]}.members"
  end

  get "*" do
    raise "Route Missing to: #{request.path}"
  end

  private

  def response_file(file_name)
    File.join(
      File.dirname(__FILE__),
      "fixtures",
      "#{@test_name}_#{file_name}.json"
    )
  end

  def json_response(response_code, file_name)
    content_type :json
    status response_code
    File.open(response_file(file_name), "rb").read
  end
end

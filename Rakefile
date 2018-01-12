require "rspec/core/rake_task"

netrc_file="spec/_fake_netrc"
File.chmod(0600, netrc_file)
ENV['OCTOKIT_NETRC_FILE']=netrc_file

RSpec::Core::RakeTask.new(:spec)

task :syntaxcheck do
  system("find ./ -not -path './vendor*' -name '*.rb' | while read f ; do echo -n \"Syntaxcheck $f: \"; ruby -wc $f || exit $? ; done")
  exit $?.exitstatus
end

task default: [
  :spec,
  :syntaxcheck
]

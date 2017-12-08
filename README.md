# github_pr

`github_pr` is a tool to fetch, filter and react on github pull requests.

The goal of `github_pr` is to fetch all open pull requests, filter them through a chain of filters and trigger events at any point in the filter chain.

The filter chain for `github_pr` is defined in a yaml configuration file and it can be enhanced with custom code. During filter processing actions can be triggered on the pull requests that match the previous filter as well as the ones that do not match. Filters and actions can be implemented with custom code. To save API requests `github_pr` caches user and team information while it is running.

# Use case

The use case for `github_pr` is the integration of continuous integration systems to your github project. Many CI tool already support github integration. But they are lacking a powerful and flexible filtering engine.

The SUSE Cloud Team is using this tool to decide which of the pull requests trigger a CI run and also compute the parameters. The CI job then reports back (also using `github_pr`) the success of the CI job as a github status. `github_pr` is a replacement for the [`github-status.rb`](https://github.com/SUSE-Cloud/automation/blob/master/scripts/github-status/github-status.rb) of the [SUSE-Cloud/automation](https://github.com/SUSE-Cloud/automation) repo. It was extracted from the cloud repo because `github_pr` is a generic tool now and can be configured to individual needs.

## Functions
Aside from filtering pull requests `github_pr` also offers some special (or short cut) functions. The desired action is defined as commandline parameter:
```shell
github_pr.rb -a <action-name> ...
```

These are all possible functions:

### trigger-prs

This runs a filterchain and triggers all defined actions.

### list-prs

This runs a filterchain but only prints the pull requests that matched all filters. This is included for backwards compatibility to *github-status.rb* and may be useful for debugging.

### set-status

This sets a status for a specific pull request (no filterchain run).  See help for details about parameters.

### pr-info

This prints the details of a pull requests (or the requested information bit). See help for details about parameters.

### is-latest-sha

This checks if the defined sha1 sum is the latest one in the defined pull request. See help for details about parameters.

### get-latest-sha

This fetches the latest sha1 sum of a pull request. See help for details about parameters.

# Requirements

`github_pr` requires ruby >= 2.1, the gems listed in the [Gemfile](Gemfile) and assumes that you have a `~/.netrc` file with your github credentials, e.g.
```
machine api.github.com
  login my-github-username
  password my-api-token
```

# How does it work?

## Workflow

To better understand what `github_pr` does internally this diagram shows the basic workflow:

![Basic Workflow](https://g.gravizo.com/source/basic_workflow?https%3A%2F%2Fraw.githubusercontent.com%2FopenSUSE%2Fgithub-pr%2Fmaster%2FREADME.md)
<details>
<summary>Basic Workflow</summary>
basic_workflow
  digraph G {
    aize ="4,4";
    fetch [label="fetch PRs"];
    filterchain [shape=box];
    fetch -> filterchain;
    config [shape=box];
    config -> filterchain [style=dotted];
    filterchain -> filter;
    blacklist [shape=box];
    whitelist [shape=box];
    filter -> blacklist;
    actionsb  [label="b actions"];
    filter -> whitelist;
    actionsw  [label="w actions"];
    blacklist -> actionsb;
    whitelist -> actionsw;
    whitelist -> filterchain;
  }
basic_workflow
</details>


## Filterchain

The filterchain consists of any number of filters (ordered list) together with optional actions for the pull requests that match the filter and for those who do not match.
For both the **whitelist** and **blacklist** there can be any number of actions.

Filters and actions can be written by custom code or just use the classes that `github_pr` ships.

## Included Filter Classes

### MergeBranch

This filter will match the target branch of the pull request. 1 or more branch names can be defined.

### Status

The status filter matches the *github status* of the last commit of this pull request. There are four possible *status* values:
1. unseen: no status exists for this commit (for the respective context, see 'pr_processing')
1. rebuild: unseen + *pending* status (a CI build is in progress)
1. forcerebuild: rebuild + *failure* status
1. all: all open pull requests (incl. *success* status)

### TrustedSource

This filter matches the author of the pull request. A list of allowed authors can be defined as well as a list of teams that are checked for the author being a member in one of them.

### FileMatch

The changed files in the pull request are matched against a list of regexp expressions. This can be used eg. to check if files are touched in this pull request that necessitate a CI run.

Note: While the above filters either do not cost an extra API requests or at least data can be cached (TrustedSource) this filter costs one or more API requests per pull request.


## Included Action Classes

After each filter process the defined actions for this filter step are executed before going to the next iteration.

### SetStatus

This action can set the *github status*. The status for a specific context (see 'pr_processing') can be set to **pending**, **failure** or **success** together with a message and a URL.

### RunCommand

This action can execute arbitrary commands. There is not much use in this basic class (no data from the pull request is passed to the command), as it is meant to inherit from and extend it (see eg. the JenkinsJobTriggerAction and JenkinsJobTriggerMkcloudAction in the [SUSE-Cloud/automation](https://github.com/SUSE-Cloud/automation) repo).

# Configuration

There is an [example](github_pr_example.yaml) configuration file that shows all natively supported filters and actions.
This example configuration includes many comments and detail descriptions.

Filters and action classes can be implemented with custom code (and be version controlled together with the configuration file).
The file name(s) have to match `ia_*.rb` (= **i**nter**a**ction file).
The directories that hold these file has to be defined either in the configuration file or as command line parameter:

In the configuration file:
```yaml
interaction_dirs:
  - /some/where/interactions
  # also possible, relative to the configuration file:
  - ./relative/path/interactions
```

As commandline parameter:
```shell
./github_pr.rb -a trigger-prs -m unseen -c github_pr_project1.yaml --interaction_dirs /here,/and/there
```

Here is an example how to implement a custom filter and an action:

```ruby
module GithubPR
  # 'filter' classes inherit from 'Filter'
  # 'action' classes inherit from 'Action'

  class MyCustomFilter < Filter
    # for each PR the method 'filter_applies?' is called and the pull request object is passed
    # define this function
    def filter_applies?(pull)
      pull.number > 1000
    end
  end

  class MyCustomAction < Action
    # for each PR the method 'action' is called and the pull request object is passed
    # define this function:
    def action(pull)
      do_something_with_eg(pull.head.sha)
    end
  end
end
```


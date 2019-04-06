# PR Tag Release Script

This is a simple bash script to generate a tag on a merged PR.  It also sets
relevent environment variables so that a Travis release is easy. See the
included `.travis.yml` for an example.

The available configuration environment variables are shown below. Keep in mind
that the `PRERELEASE_REGEX` and `DRAFT_REGEX` are applied to the ***title*** of
the Pull Request, unlike the others, which apply to the body.

```bash
DEPLOY_BRANCH=${DEPOY_BRANCH-"^master$"}
MERGE_COMMIT_REGEX=${MERGE_COMMIT_REGEX-"Merge pull request #([0-9]+)"}
PATCH_CHANGE_REGEX=${PATCH_CHANGE_REGEX-"This (PR|release) is an?( small| tiny)? (update|bugfix)"}
MINOR_CHANGE_REGEX=${MINOR_CHANGE_REGEX-"This (PR|release) is a (feature( update| change)?|big (update|change))"}
MAJOR_CHANGE_REGEX=${MAJOR_CHANGE_REGEX-"This (PR|release) (is a ((compatibility[ -])?breaking|major) (update|change)| breaks( backwards)? compatibility)"}
PRERELEASE_REGEX=${PRERELEASE_REGEX-"\[(PRE|WIP|PRERELEASE)\]"}
DRAFT_REGEX=${DRAFT_REGEX-"\[(WIP|DRAFT)\]"}
```

Including the below `yaml` in your `.travis.yml` and providing the
`$GITHUB_OAUTH_TOKEN` enviroment variable will enable auto-generated releases.

```yaml
after_success:
  - wget https://github.com/Michionlion/pr-tag-release/releases/latest/download/pr_tag_release.sh
  - source pr_tag_release.sh
deploy:
  provider: releases
  api_key: "$GITHUB_OAUTH_TOKEN"
  file: pr_tag_release.sh
  skip_cleanup: true
  on:
    all_branches: true
    condition: $DO_GITHUB_RELEASE = true
```

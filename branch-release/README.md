# branch-release
This action is indended to create/update release branches and merge changes forward to more recent releases.
It should trigger on release tag creation; this action will extract the apparent release number ("YY.M") from the tag.

### Initial Release Branch Creation
When a tag is created for a non-existent release, this action will create `releaseYY.M` and `releaseYY.M-SNAPSHOT` branches at the tagged commit.
It is expected that such a tag be created on the `develop` branch.

### Maintenance Release Pull Requests
When a tag is created for an existing release, this action assumes that the tag represents a new maintenance release.
It creates two new branches and pull requests:

###### Update release branch
Creates a placeholder branch at the tagged commit (`ff_YY.M.P`) and opens a PR to `releaseYY.M`.

###### Merge forward toward develop
_The merge forward target will be the next most recent non-monthly release snapshot branch or develop._  
This action creates a new feature branch at the merge forward target branch. It then merges the tagged commit into that branch and opens a pull request to the merge forward target branch.  
(e.g. `fb_merge_20.7.0 => develop` or `20.7_fb_merge_20.3.6 => release20.7-SNAPSHOT`)

_Note: Merging these PRs is handled by the `merge_release` action._